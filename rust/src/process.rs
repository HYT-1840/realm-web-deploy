use anyhow::{Result, bail};
use tokio::process::Command;
use std::process::Stdio;
use std::time::Duration;
use tokio::time::sleep;
use psutil::process::Process;
use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;

use crate::db::{Connection, update_rule_status, get_rule_by_id};
use crate::models::Rule;

// Realm可执行文件路径（与原Python一致）
pub const REALM_BIN: &str = "/usr/local/bin/realm";

/// 启动Realm进程（返回PID）
pub async fn start_realm(rule: &Rule) -> Result<u32> {
    // 构建Realm命令：realm listen 0.0.0.0:port target
    let cmd = Command::new(REALM_BIN)
        .arg("listen")
        .arg(format!("0.0.0.0:{}", rule.local_port))
        .arg(&rule.target)
        .stdout(Stdio::null()) // 重定向输出到空
        .stderr(Stdio::null())
        .spawn(); // 后台启动

    match cmd {
        Ok(mut child) => {
            let pid = child.id().ok_or_else(|| anyhow::anyhow!("获取进程PID失败"))?;
            // 等待1秒确保进程启动成功
            sleep(Duration::from_secs(1)).await;
            // 检查进程是否仍在运行
            if Process::new(pid as i32).is_ok() {
                Ok(pid)
            } else {
                bail!("Realm进程启动后立即退出");
            }
        }
        Err(e) => bail!("启动Realm进程失败：{}", e),
    }
}

/// 停止Realm进程（先优雅退出SIGTERM，失败则强制杀死SIGKILL）
pub fn stop_realm(pid: i32) -> Result<()> {
    let pid = Pid::from_raw(pid);
    // 先尝试优雅退出
    if let Err(e) = kill(pid, Signal::SIGTERM) {
        eprintln!("优雅停止进程失败，尝试强制杀死：{}", e);
        // 强制杀死
        kill(pid, Signal::SIGKILL)?;
    }
    // 等待进程退出
    std::thread::sleep(Duration::from_secs(1));
    Ok(())
}

/// 定时检查Realm进程状态（后台守护，每10秒检查一次）
pub async fn check_realm_processes(mut conn: Connection) {
    loop {
        match check_all_running_processes(&mut conn).await {
            Ok(_) => (),
            Err(e) => eprintln!("检查Realm进程状态失败：{}", e),
        }
        // 每10秒检查一次
        sleep(Duration::from_secs(10)).await;
    }
}

/// 检查所有运行中的Realm进程，异常则更新状态为stop
async fn check_all_running_processes(conn: &mut Connection) -> Result<()> {
    // 查询所有运行中的规则
    let mut stmt = conn.prepare(
        "SELECT id, pid FROM realm_rules WHERE status = 'run' AND pid > 0"
    ).await?;

    let rows = stmt.query_map(params![], |row| Ok((
        row.get::<_, i32>(0)?,
        row.get::<_, i32>(1)?,
    ))).await?;

    for row in rows {
        let (rule_id, pid) = row?;
        // 检查进程是否存在
        if Process::new(pid).is_err() {
            // 进程不存在，更新状态为stop，PID置0
            update_rule_status(conn, rule_id, "stop", 0).await?;
            eprintln!("进程PID:{}已退出，更新规则{}状态为stop", pid, rule_id);
        }
    }

    Ok(())
}
