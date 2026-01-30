use anyhow::{Context, Result};
use tokio_rusqlite::Connection;
use rusqlite::params;
use chrono::NaiveDateTime;
use std::path::Path;

use crate::models::{User, Rule};

// 数据库文件路径（与原Python一致：/opt/realm-web/realm.db）
pub const DB_PATH: &str = "/opt/realm-web/realm.db";

/// 初始化数据库（创表+若不存在则添加管理员）
pub async fn init_db(admin_user: &str, admin_pwd: &str) -> Result<()> {
    // 连接数据库（不存在则自动创建）
    let conn = Connection::open(DB_PATH).await.context("打开数据库失败")?;
    
    // 创建用户表（与原Python完全一致，SQLite兼容）
    conn.execute(
        r#"CREATE TABLE IF NOT EXISTS realm_users
        (id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'user',
        create_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP)"#,
        params![],
    ).await.context("创建用户表失败")?;

    // 创建规则表（与原Python完全一致，外键关联）
    conn.execute(
        r#"CREATE TABLE IF NOT EXISTS realm_rules
        (id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL,
        local_port INTEGER UNIQUE NOT NULL,
        target TEXT NOT NULL,
        remark TEXT DEFAULT '',
        pid INTEGER DEFAULT 0,
        status TEXT DEFAULT 'stop',
        create_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (username) REFERENCES realm_users (username))"#,
        params![],
    ).await.context("创建规则表失败")?;

    // 检查管理员是否存在，不存在则创建
    if !check_user_exists(&conn, admin_user).await? {
        conn.execute(
            "INSERT INTO realm_users (username, password, role) VALUES (?, ?, 'super_admin')",
            params![admin_user, admin_pwd],
        ).await.context("创建管理员失败")?;
        println!("✅ 管理员账号创建成功：{}", admin_user);
    } else {
        println!("⚠️  管理员账号{}已存在，跳过创建", admin_user);
    }

    Ok(())
}

/// 检查用户是否存在
pub async fn check_user_exists(conn: &Connection, username: &str) -> Result<bool> {
    let count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM realm_users WHERE username = ?",
        params![username],
        |row| row.get(0),
    ).await?;
    Ok(count > 0)
}

/// 根据用户名和密码查询用户（登录验证）
pub async fn get_user_by_auth(conn: &Connection, username: &str, pwd: &str) -> Result<Option<User>> {
    let row = conn.query_row(
        "SELECT id, username, password, role, create_time FROM realm_users WHERE username = ? AND password = ?",
        params![username, pwd],
        |row| Ok(User {
            id: row.get(0)?,
            username: row.get(1)?,
            password: row.get(2)?,
            role: row.get(3)?,
            create_time: row.get(4)?,
        }),
    ).await;

    match row {
        Ok(user) => Ok(Some(user)),
        Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
        Err(e) => Err(e.into()),
    }
}

/// 根据用户名查询规则（普通用户仅查自己，管理员查所有）
pub async fn get_rules_by_user(conn: &Connection, username: &str, role: &str) -> Result<Vec<Rule>> {
    let mut rules = Vec::new();
    let sql = if role == "super_admin" || role == "admin" {
        "SELECT id, username, local_port, target, remark, pid, status, create_time FROM realm_rules ORDER BY id DESC"
    } else {
        "SELECT id, username, local_port, target, remark, pid, status, create_time FROM realm_rules WHERE username = ? ORDER BY id DESC"
    };

    let mut stmt = conn.prepare(sql).await?;
    let rows = if role == "super_admin" || role == "admin" {
        stmt.query_map(params![], |row| Ok(Rule {
            id: row.get(0)?,
            username: row.get(1)?,
            local_port: row.get(2)?,
            target: row.get(3)?,
            remark: row.get(4)?,
            pid: row.get(5)?,
            status: row.get(6)?,
            create_time: row.get(7)?,
        })).await?
    } else {
        stmt.query_map(params![username], |row| Ok(Rule {
            id: row.get(0)?,
            username: row.get(1)?,
            local_port: row.get(2)?,
            target: row.get(3)?,
            remark: row.get(4)?,
            pid: row.get(5)?,
            status: row.get(6)?,
            create_time: row.get(7)?,
        })).await?
    };

    for row in rows {
        rules.push(row?);
    }
    Ok(rules)
}

/// 新增规则
pub async fn add_rule(
    conn: &Connection,
    username: &str,
    local_port: i32,
    target: &str,
    remark: &Option<String>,
) -> Result<()> {
    // 检查端口是否已存在
    let count: i64 = conn.query_row(
        "SELECT COUNT(*) FROM realm_rules WHERE local_port = ?",
        params![local_port],
        |row| row.get(0),
    ).await?;
    if count > 0 {
        anyhow::bail!("本地端口已被使用");
    }

    // 插入规则
    conn.execute(
        "INSERT INTO realm_rules (username, local_port, target, remark) VALUES (?, ?, ?, ?)",
        params![username, local_port, target, remark.as_deref().unwrap_or("")],
    ).await.context("新增规则失败")?;

    Ok(())
}

/// 更新规则状态和PID（启动/停止规则时调用）
pub async fn update_rule_status(
    conn: &Connection,
    rule_id: i32,
    status: &str,
    pid: i32,
) -> Result<()> {
    conn.execute(
        "UPDATE realm_rules SET status = ?, pid = ? WHERE id = ?",
        params![status, pid, rule_id],
    ).await.context("更新规则状态失败")?;
    Ok(())
}

/// 根据ID删除规则
pub async fn delete_rule(conn: &Connection, rule_id: i32) -> Result<()> {
    conn.execute(
        "DELETE FROM realm_rules WHERE id = ?",
        params![rule_id],
    ).await.context("删除规则失败")?;
    Ok(())
}

/// 根据ID查询规则
pub async fn get_rule_by_id(conn: &Connection, rule_id: i32) -> Result<Option<Rule>> {
    let row = conn.query_row(
        "SELECT id, username, local_port, target, remark, pid, status, create_time FROM realm_rules WHERE id = ?",
        params![rule_id],
        |row| Ok(Rule {
            id: row.get(0)?,
            username: row.get(1)?,
            local_port: row.get(2)?,
            target: row.get(3)?,
            remark: row.get(4)?,
            pid: row.get(5)?,
            status: row.get(6)?,
            create_time: row.get(7)?,
        }),
    ).await;

    match row {
        Ok(rule) => Ok(Some(rule)),
        Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
        Err(e) => Err(e.into()),
    }
}
