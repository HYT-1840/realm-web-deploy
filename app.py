import os
import sys
import psutil
import subprocess
import json
from flask import Flask, render_template, request, jsonify, redirect, url_for, session
from flask_login import LoginManager, UserMixin, login_user, login_required, logout_user, current_user
from flask_cors import CORS
import sqlite3
from werkzeug.security import generate_password_hash, check_password_hash

# 初始化Flask应用
app = Flask(__name__)
app.config['SECRET_KEY'] = 'realm-web-2026-custom-key'  # 建议部署时修改为随机值
app.config['PERMANENT_SESSION_LIFETIME'] = 3600 * 24  # 会话有效期1天
CORS(app)
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'  # 未登录重定向到登录页

# === SQLite数据库初始化（支持传入管理员账号密码）===
def init_db(admin_user="admin", admin_pwd="123456"):
    db_path = os.path.join(os.path.dirname(__file__), 'realm.db')
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    # 1. 用户表（多用户隔离核心）
    c.execute('''CREATE TABLE IF NOT EXISTS users
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  username TEXT UNIQUE NOT NULL,
                  password TEXT NOT NULL,
                  create_time DATETIME DEFAULT CURRENT_TIMESTAMP)''')
    # 2. Realm转发规则表（绑定用户ID，实现规则隔离）
    c.execute('''CREATE TABLE IF NOT EXISTS realm_rules
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  user_id INTEGER NOT NULL,
                  local_port INTEGER UNIQUE NOT NULL,
                  target TEXT NOT NULL,
                  pid INTEGER DEFAULT 0,
                  status TEXT DEFAULT 'stop',  # run/stop
                  create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
                  FOREIGN KEY (user_id) REFERENCES users(id))''')
    conn.commit()
    # 创建管理员用户（不存在时）
    if not db_query('SELECT * FROM users WHERE username=?', (admin_user,)):
        hashed_pwd = generate_password_hash(admin_pwd, method='pbkdf2:sha256')
        db_execute('INSERT INTO users (username, password) VALUES (?, ?)', (admin_user, hashed_pwd))
    conn.close()

# 数据库通用操作函数
def db_query(sql, args=()):
    db_path = os.path.join(os.path.dirname(__file__), 'realm.db')
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    c.execute(sql, args)
    res = [dict(row) for row in c.fetchall()]
    conn.close()
    return res

def db_execute(sql, args=()):
    db_path = os.path.join(os.path.dirname(__file__), 'realm.db')
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    try:
        c.execute(sql, args)
        conn.commit()
        return True
    except Exception as e:
        print(f"数据库错误：{e}")
        conn.rollback()
        return False
    finally:
        conn.close()

# === 用户模型与鉴权 ===
class User(UserMixin):
    def __init__(self, id, username):
        self.id = id
        self.username = username

@login_manager.user_loader
def load_user(user_id):
    res = db_query('SELECT id, username FROM users WHERE id=?', (user_id,))
    if res:
        return User(res[0]['id'], res[0]['username'])
    return None

# === Realm进程/端口管控工具函数 ===
def is_port_used(port):
    try:
        for conn in psutil.net_connections(kind='inet'):
            if conn.laddr.port == port:
                return True
        return False
    except:
        return False

def stop_process(pid):
    try:
        if psutil.pid_exists(pid):
            p = psutil.Process(pid)
            p.terminate()
            p.wait(timeout=5)
        return True
    except:
        return False

def start_realm(local_port, target):
    if is_port_used(local_port):
        return False, "端口已被占用"
    realm_cmd = 'realm.exe' if sys.platform == 'win32' else 'realm'
    cmd = [realm_cmd, 'relay', '-l', f'0.0.0.0:{local_port}', '-r', target]
    try:
        p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return p.pid, "启动成功"
    except Exception as e:
        return False, f"启动失败：{str(e)[:50]}"

# === 页面路由 ===
@app.route('/')
@login_required
def index():
    return render_template('index.html', username=current_user.username)

@app.route('/login')
def login():
    return render_template('login.html')

# === 核心接口（前后端交互）===
@app.route('/api/login', methods=['POST'])
def api_login():
    data = request.json
    username = data.get('username')
    password = data.get('password')
    if not username or not password:
        return jsonify({'code': 1, 'msg': '账号/密码不能为空'})
    user_res = db_query('SELECT id, password FROM users WHERE username=?', (username,))
    if not user_res:
        return jsonify({'code': 1, 'msg': '账号不存在'})
    if check_password_hash(user_res[0]['password'], password):
        user = User(user_res[0]['id'], username)
        login_user(user, remember=True)
        return jsonify({'code': 0, 'msg': '登录成功'})
    else:
        return jsonify({'code': 1, 'msg': '密码错误'})

@app.route('/api/logout', methods=['POST'])
@login_required
def api_logout():
    logout_user()
    return jsonify({'code': 0, 'msg': '登出成功'})

@app.route('/api/add_user', methods=['POST'])
@login_required
def api_add_user():
    data = request.json
    username = data.get('username')
    password = data.get('password')
    if not username or not password:
        return jsonify({'code': 1, 'msg': '账号/密码不能为空'})
    if db_query('SELECT * FROM users WHERE username=?', (username,)):
        return jsonify({'code': 1, 'msg': '用户已存在'})
    if db_execute('INSERT INTO users (username, password) VALUES (?, ?)',
                   (username, generate_password_hash(password, method='pbkdf2:sha256'))):
        return jsonify({'code': 0, 'msg': '用户创建成功'})
    else:
        return jsonify({'code': 1, 'msg': '用户创建失败'})

@app.route('/api/add_rule', methods=['POST'])
@login_required
def api_add_rule():
    data = request.json
    local_port = int(data.get('local_port', 0))
    target = data.get('target', '').strip()
    if not local_port or not target or local_port < 1024 or local_port > 65535:
        return jsonify({'code': 1, 'msg': '端口/目标地址格式错误（端口1024-65535）'})
    if db_query('SELECT * FROM realm_rules WHERE local_port=?', (local_port,)) or is_port_used(local_port):
        return jsonify({'code': 1, 'msg': '端口已被占用/已配置'})
    if db_execute('INSERT INTO realm_rules (user_id, local_port, target) VALUES (?, ?, ?)',
                   (current_user.id, local_port, target)):
        return jsonify({'code': 0, 'msg': '规则添加成功'})
    else:
        return jsonify({'code': 1, 'msg': '规则添加失败'})

@app.route('/api/get_rules', methods=['GET'])
@login_required
def api_get_rules():
    rules = db_query('SELECT * FROM realm_rules WHERE user_id=?', (current_user.id,))
    return jsonify({'code': 0, 'data': rules})

@app.route('/api/start_rule', methods=['POST'])
@login_required
def api_start_rule():
    data = request.json
    rule_id = int(data.get('rule_id', 0))
    rule = db_query('SELECT * FROM realm_rules WHERE id=? AND user_id=?', (rule_id, current_user.id))
    if not rule:
        return jsonify({'code': 1, 'msg': '规则不存在'})
    rule = rule[0]
    if rule['status'] == 'run':
        return jsonify({'code': 1, 'msg': '规则已在运行'})
    pid, msg = start_realm(rule['local_port'], rule['target'])
    if pid:
        db_execute('UPDATE realm_rules SET pid=?, status=? WHERE id=?', (pid, 'run', rule_id))
        return jsonify({'code': 0, 'msg': msg})
    else:
        return jsonify({'code': 1, 'msg': msg})

@app.route('/api/stop_rule', methods=['POST'])
@login_required
def api_stop_rule():
    data = request.json
    rule_id = int(data.get('rule_id', 0))
    rule = db_query('SELECT * FROM realm_rules WHERE id=? AND user_id=?', (rule_id, current_user.id))
    if not rule:
        return jsonify({'code': 1, 'msg': '规则不存在'})
    rule = rule[0]
    if rule['status'] == 'stop':
        return jsonify({'code': 1, 'msg': '规则已停止'})
    if stop_process(rule['pid']):
        db_execute('UPDATE realm_rules SET pid=0, status=? WHERE id=?', ('stop', rule_id))
        return jsonify({'code': 0, 'msg': '停止成功'})
    else:
        db_execute('UPDATE realm_rules SET pid=0, status=? WHERE id=?', ('stop', rule_id))
        return jsonify({'code': 0, 'msg': '进程已异常，强制更新状态为停止'})

@app.route('/api/delete_rule', methods=['POST'])
@login_required
def api_delete_rule():
    data = request.json
    rule_id = int(data.get('rule_id', 0))
    rule = db_query('SELECT * FROM realm_rules WHERE id=? AND user_id=?', (rule_id, current_user.id))
    if not rule:
        return jsonify({'code': 1, 'msg': '规则不存在'})
    rule = rule[0]
    if rule['status'] == 'run':
        stop_process(rule['pid'])
    if db_execute('DELETE FROM realm_rules WHERE id=?', (rule_id,)):
        return jsonify({'code': 0, 'msg': '规则删除成功'})
    else:
        return jsonify({'code': 1, 'msg': '规则删除失败'})

# === 初始化入口（支持命令行传入管理员账号密码）===
if __name__ == '__main__':
    admin_user = sys.argv[1] if len(sys.argv) > 1 else 'admin'
    admin_pwd = sys.argv[2] if len(sys.argv) > 2 else '123456'
    init_db(admin_user, admin_pwd)
    app.run(host='0.0.0.0', port=5000, debug=False)  # 生产环境禁用debug
