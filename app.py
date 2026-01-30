import sqlite3
import os
import sys
import json
import psutil
import subprocess
import time
from flask import Flask, render_template, request, jsonify, redirect, url_for, session
from flask_login import LoginManager, UserMixin, login_user, login_required, logout_user, current_user
from flask_cors import CORS
import signal

# ===================== 基础配置 =====================
app = Flask(__name__, template_folder='templates')
CORS(app)
# 密钥从环境变量获取，部署脚本自动生成
app.secret_key = os.environ.get('REALM_SECRET_KEY', 'default-secret-key-for-dev')
# 服务端口从环境变量获取，部署脚本指定
PORT = int(os.environ.get('REALM_PORT', 5000))
# 数据库文件路径
DB_FILE = os.path.join(os.path.dirname(__file__), 'realm.db')
# Realm可执行文件路径（系统级，部署脚本已安装）
REALM_BIN = '/usr/local/bin/realm'
# 登录管理器初始化
login_manager = LoginManager()
login_manager.init_app(app)
login_manager.login_view = 'login'

# ===================== 数据库工具函数 =====================
def get_db_connection():
    """获取数据库连接"""
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row  # 支持按列名访问
    return conn

def init_db(admin_user, admin_pwd):
    """初始化数据库，创建用户表和规则表，添加默认管理员（修复SQLite注释语法）"""
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()

    # 创建用户表 - SQLite兼容注释（--）
    c.execute('''CREATE TABLE IF NOT EXISTS realm_users
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  username TEXT UNIQUE NOT NULL,
                  password TEXT NOT NULL,
                  role TEXT NOT NULL DEFAULT 'user',  -- 角色：super_admin/admin/user
                  create_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP)''')

    # 创建规则表 - SQLite兼容注释（--），修复原#注释报错问题
    c.execute('''CREATE TABLE IF NOT EXISTS realm_rules
                 (id INTEGER PRIMARY KEY AUTOINCREMENT,
                  username TEXT NOT NULL,  -- 所属用户
                  local_port INTEGER UNIQUE NOT NULL,  -- 本地监听端口
                  target TEXT NOT NULL,  -- 目标地址（ip:port）
                  remark TEXT DEFAULT '',  -- 规则备注
                  pid INTEGER DEFAULT 0,  -- 进程ID
                  status TEXT DEFAULT 'stop',  -- 运行状态：run/stop
                  create_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                  FOREIGN KEY (username) REFERENCES realm_users (username))''')

    # 检查并创建默认管理员
    c.execute("SELECT * FROM realm_users WHERE username = ?", (admin_user,))
    if not c.fetchone():
        c.execute("INSERT INTO realm_users (username, password, role) VALUES (?, ?, 'super_admin')",
                  (admin_user, admin_pwd))
        print(f"✅ 管理员账号创建成功：{admin_user}")
    else:
        print(f"⚠️  管理员账号{admin_user}已存在，跳过创建")

    conn.commit()
    conn.close()
    print("✅ 数据库初始化完成！")

# ===================== Flask-Login 用户模型 =====================
class User(UserMixin):
    def __init__(self, id, username, role):
        self.id = id
        self.username = username
        self.role = role

@login_manager.user_loader
def load_user(user_id):
    """加载用户信息"""
    conn = get_db_connection()
    user = conn.execute("SELECT * FROM realm_users WHERE id = ?", (user_id,)).fetchone()
    conn.close()
    if user:
        return User(user['id'], user['username'], user['role'])
    return None

# ===================== 路由 - 页面访问 =====================
@app.route('/')
@login_required
def index():
    """主页面，传递用户名和角色（用于前端权限控制）"""
    return render_template('index.html', username=current_user.username, role=current_user.role)

@app.route('/login')
def login_page():
    """登录页面"""
    if current_user.is_authenticated:
        return redirect(url_for('index'))
    return render_template('login.html')

# ===================== 路由 - 认证接口 =====================
@app.route('/api/login', methods=['POST'])
def login():
    """用户登录接口"""
    data = request.get_json()
    username = data.get('username', '').strip()
    password = data.get('password', '').strip()

    if not username or not password:
        return jsonify({'code': 1, 'msg': '用户名和密码不能为空'})

    conn = get_db_connection()
    user = conn.execute("SELECT * FROM realm_users WHERE username = ?", (username,)).fetchone()
    conn.close()

    if user and user['password'] == password:
        user_obj = User(user['id'], user['username'], user['role'])
        login_user(user_obj)
        return jsonify({'code': 0, 'msg': '登录成功'})
    else:
        return jsonify({'code': 1, 'msg': '用户名或密码错误'})

@app.route('/api/logout', methods=['POST'])
@login_required
def logout():
    """用户登出接口"""
    logout_user()
    return jsonify({'code': 0, 'msg': '登出成功'})

# ===================== 路由 - 用户管理接口（仅管理员） =====================
@app.route('/api/add_user', methods=['POST'])
@login_required
def add_user():
    """添加子用户（仅super_admin/admin可操作）"""
    if current_user.role == 'user':
        return jsonify({'code': 1, 'msg': '无权限添加用户'})

    data = request.get_json()
    username = data.get('username', '').strip()
    password = data.get('password', '').strip()

    if not username or len(username) < 3:
        return jsonify({'code': 1, 'msg': '用户名至少3位'})
    if not password or len(password) < 6:
        return jsonify({'code': 1, 'msg': '密码至少6位'})

    try:
        conn = get_db_connection()
        # 检查用户名是否已存在
        if conn.execute("SELECT * FROM realm_users WHERE username = ?", (username,)).fetchone():
            conn.close()
            return jsonify({'code': 1, 'msg': '用户名已存在'})
        # 添加子用户（默认角色user）
        conn.execute("INSERT INTO realm_users (username, password, role) VALUES (?, ?, 'user')",
                     (username, password))
        conn.commit()
        conn.close()
        return jsonify({'code': 0, 'msg': '子用户创建成功'})
    except Exception as e:
        return jsonify({'code': 1, 'msg': f'创建失败：{str(e)}'})

# ===================== 路由 - 规则管理核心接口 =====================
@app.route('/api/add_rule', methods=['POST'])
@login_required
def add_rule():
    """添加转发规则"""
    data = request.get_json()
    local_port = data.get('local_port', '')
    target = data.get('target', '').strip()
    remark = data.get('remark', '').strip()

    # 基础校验
    if not local_port or not target:
        return jsonify({'code': 1, 'msg': '端口和目标地址不能为空'})
    try:
        local_port = int(local_port)
        if not (1024 <= local_port <= 65535):
            return jsonify({'code': 1, 'msg': '端口必须在1024-65535之间'})
    except ValueError:
        return jsonify({'code': 1, 'msg': '端口必须是数字'})
    if ':' not in target:
        return jsonify({'code': 1, 'msg': '目标地址格式错误（例：192.168.1.100:80）'})

    try:
        conn = get_db_connection()
        # 检查端口是否已被占用
        if conn.execute("SELECT * FROM realm_rules WHERE local_port = ?", (local_port,)).fetchone():
            conn.close()
            return jsonify({'code': 1, 'msg': '本地端口已被使用'})
        # 添加规则
        conn.execute('''INSERT INTO realm_rules (username, local_port, target, remark)
                        VALUES (?, ?, ?, ?)''', (current_user.username, local_port, target, remark))
        conn.commit()
        conn.close()
        return jsonify({'code': 0, 'msg': '规则添加成功'})
    except Exception as e:
        return jsonify({'code': 1, 'msg': f'添加失败：{str(e)}'})

@app.route('/api/get_rules', methods=['GET'])
@login_required
def get_rules():
    """获取当前用户的所有规则（管理员可看所有，普通用户仅看自己）"""
    try:
        conn = get_db_connection()
        if current_user.role in ['super_admin', 'admin']:
            # 管理员查看所有规则
            rules = conn.execute("SELECT * FROM realm_rules ORDER BY id DESC").fetchall()
        else:
            # 普通用户仅查看自己的规则
            rules = conn.execute('''SELECT * FROM realm_rules WHERE username = ?
                                    ORDER BY id DESC''', (current_user.username,)).fetchall()
        conn.close()
        # 转换为字典列表返回
        result = [dict(rule) for rule in rules]
        return jsonify({'code': 0, 'msg': '获取成功', 'data': result})
    except Exception as e:
        return jsonify({'code': 1, 'msg': f'获取失败：{str(e)}', 'data': []})

def stop_realm_process(pid):
    """停止Realm进程（通用函数）"""
    try:
        if psutil.pid_exists(pid):
            os.kill(pid, signal.SIGTERM)
            # 等待进程退出
            time.sleep(1)
            if psutil.pid_exists(pid):
                os.kill(pid, signal.SIGKILL)
        return True
    except Exception as e:
        print(f"停止进程失败：{e}")
        return False

@app.route('/api/start_rule', methods=['POST'])
@login_required
def start_rule():
    """启动转发规则（适配Realm新包命名，直接调用系统realm）"""
    data = request.get_json()
    rule_id = data.get('rule_id')
    if not rule_id:
        return jsonify({'code': 1, 'msg': '规则ID不能为空'})

    try:
        conn = get_db_connection()
        rule = conn.execute("SELECT * FROM realm_rules WHERE id = ?", (rule_id,)).fetchone()
        # 校验规则归属（普通用户只能操作自己的规则）
        if rule['username'] != current_user.username and current_user.role == 'user':
            conn.close()
            return jsonify({'code': 1, 'msg': '无权限操作该规则'})
        # 检查规则状态
        if rule['status'] == 'run':
            conn.close()
            return jsonify({'code': 1, 'msg': '规则已在运行中'})

        # 启动Realm进程（适配官方新包，直接调用/usr/local/bin/realm）
        cmd = [REALM_BIN, 'listen', f'0.0.0.0:{rule["local_port"]}', rule["target"]]
        # 后台运行，重定向输出
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # 更新规则状态和PID
        conn.execute('''UPDATE realm_rules SET status = 'run', pid = ? WHERE id = ?''',
                     (proc.pid, rule_id))
        conn.commit()
        conn.close()
        return jsonify({'code': 0, 'msg': '规则启动成功'})
    except Exception as e:
        return jsonify({'code': 1, 'msg': f'启动失败：{str(e)}'})

@app.route('/api/stop_rule', methods=['POST'])
@login_required
def stop_rule():
    """停止转发规则"""
    data = request.get_json()
    rule_id = data.get('rule_id')
    if not rule_id:
        return jsonify({'code': 1, 'msg': '规则ID不能为空'})

    try:
        conn = get_db_connection()
        rule = conn.execute("SELECT * FROM realm_rules WHERE id = ?", (rule_id,)).fetchone()
        # 校验规则归属
        if rule['username'] != current_user.username and current_user.role == 'user':
            conn.close()
            return jsonify({'code': 1, 'msg': '无权限操作该规则'})
        # 检查规则状态
        if rule['status'] == 'stop':
            conn.close()
            return jsonify({'code': 1, 'msg': '规则已停止'})

        # 停止进程并更新状态
        if stop_realm_process(rule['pid']):
            conn.execute('''UPDATE realm_rules SET status = 'stop', pid = 0 WHERE id = ?''',
                         (rule_id,))
            conn.commit()
        conn.close()
        return jsonify({'code': 0, 'msg': '规则停止成功'})
    except Exception as e:
        return jsonify({'code': 1, 'msg': f'停止失败：{str(e)}'})

@app.route('/api/delete_rule', methods=['POST'])
@login_required
def delete_rule():
    """删除转发规则（先停止进程再删除）"""
    data = request.get_json()
    rule_id = data.get('rule_id')
    if not rule_id:
        return jsonify({'code': 1, 'msg': '规则ID不能为空'})

    try:
        conn = get_db_connection()
        rule = conn.execute("SELECT * FROM realm_rules WHERE id = ?", (rule_id,)).fetchone()
        # 校验规则归属
        if rule['username'] != current_user.username and current_user.role == 'user':
            conn.close()
            return jsonify({'code': 1, 'msg': '无权限操作该规则'})

        # 先停止进程
        if rule['status'] == 'run' and rule['pid'] != 0:
            stop_realm_process(rule['pid'])
        # 删除规则
        conn.execute("DELETE FROM realm_rules WHERE id = ?", (rule_id,))
        conn.commit()
        conn.close()
        return jsonify({'code': 0, 'msg': '规则删除成功'})
    except Exception as e:
        return jsonify({'code': 1, 'msg': f'删除失败：{str(e)}'})

# ===================== 进程守护 - 检查Realm进程状态 =====================
def check_realm_processes():
    """定时检查Realm进程状态，异常则更新数据库"""
    while True:
        try:
            conn = get_db_connection()
            # 查询所有运行中的规则
            running_rules = conn.execute("SELECT * FROM realm_rules WHERE status = 'run'").fetchall()
            for rule in running_rules:
                if rule['pid'] != 0 and not psutil.pid_exists(rule['pid']):
                    # 进程不存在，更新状态
                    conn.execute('''UPDATE realm_rules SET status = 'stop', pid = 0 WHERE id = ?''',
                                 (rule['id'],))
            conn.commit()
            conn.close()
        except Exception as e:
            print(f"检查进程状态失败：{e}")
        # 每10秒检查一次
        time.sleep(10)

# ===================== 主函数 - 初始化+启动服务 =====================
if __name__ == "__main__":
    # 外部传参执行数据库初始化（deploy.sh调用：python app.py 用户名 密码）
    if len(sys.argv) == 3:
        admin_user = sys.argv[1].strip()
        admin_pwd = sys.argv[2].strip()
        if admin_user and admin_pwd:
            init_db(admin_user, admin_pwd)
        else:
            print("❌ 管理员用户名和密码不能为空！")
            sys.exit(1)
    else:
        # 启动服务时，后台运行进程检查
        import threading
        process_check_thread = threading.Thread(target=check_realm_processes, daemon=True)
        process_check_thread.start()
        # 启动Flask服务（Gunicorn部署时此部分会被覆盖）
        print(f"🚀 Realm Web服务启动中，端口：{PORT}")
        app.run(host='0.0.0.0', port=PORT, debug=False)
