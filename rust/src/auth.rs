use axum::{
    extract::State,
    response::Redirect,
    http::StatusCode,
    Json,
};
use axum_sessions::extractors::Session;
use serde::Deserialize;

use crate::models::{ApiResponse, User};
use crate::db::{Connection, get_user_by_auth};
use crate::AppState;

// 登录请求体
#[derive(Debug, Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

/// 登录接口（与原Python API一致：/api/login）
pub async fn login(
    State(state): State<AppState>,
    Session(session): Session,
    Json(req): Json<LoginRequest>,
) -> Json<ApiResponse<()>> {
    // 校验参数
    if req.username.is_empty() || req.password.is_empty() {
        return Json(ApiResponse::error("用户名和密码不能为空"));
    }

    // 数据库查询用户
    let user = match get_user_by_auth(&state.db, &req.username, &req.password).await {
        Ok(Some(u)) => u,
        Ok(None) => return Json(ApiResponse::error("用户名或密码错误")),
        Err(e) => {
            eprintln!("查询用户失败：{}", e);
            return Json(ApiResponse::error("服务器内部错误"));
        }
    };

    // 设置会话（用户信息）
    session.insert("user_id", user.id).unwrap();
    session.insert("username", user.username).unwrap();
    session.insert("role", user.role).unwrap();

    Json(ApiResponse::success("登录成功"))
}

/// 登出接口（与原Python API一致：/api/logout）
pub async fn logout(Session(session): Session) -> Json<ApiResponse<()>> {
    // 清空会话
    session.clear();
    Json(ApiResponse::success("登出成功"))
}

/// 权限校验中间件（检查是否登录，可选检查角色）
pub async fn auth_middleware(
    Session(session): Session,
    mut next: axum::middleware::Next<axum::extract::Request>,
) -> Result<axum::response::Response, (StatusCode, Json<ApiResponse<()>>)> {
    // 检查是否登录
    if session.get::<String>("username").is_none() {
        return Err((
            StatusCode::OK,
            Json(ApiResponse::error("未登录，请先登录")),
        ));
    }
    Ok(next.run().await)
}

/// 角色校验中间件（仅super_admin/admin可操作）
pub async fn role_middleware(
    Session(session): Session,
    mut next: axum::middleware::Next<axum::extract::Request>,
) -> Result<axum::response::Response, (StatusCode, Json<ApiResponse<()>>)> {
    let role = match session.get::<String>("role") {
        Some(r) => r,
        None => return Err((
            StatusCode::OK,
            Json(ApiResponse::error("未登录，请先登录")),
        )),
    };

    // 仅管理员可操作
    if role != "super_admin" && role != "admin" {
        return Err((
            StatusCode::OK,
            Json(ApiResponse::error("无权限执行此操作")),
        ));
    }

    Ok(next.run().await)
}

/// 从会话中获取当前用户信息
pub fn get_current_user(Session(session): &Session) -> Option<(String, String)> {
    let username = session.get::<String>("username")?;
    let role = session.get::<String>("role")?;
    Some((username, role))
}

/// 检查规则归属（普通用户仅能操作自己的规则）
pub fn check_rule_owner(
    session: &Session,
    rule_owner: &str,
) -> bool {
    let (username, role) = match get_current_user(session) {
        Some(u) => u,
        None => return false,
    };
    // 管理员可操作所有规则，普通用户仅能操作自己的
    role == "super_admin" || role == "admin" || username == rule_owner
}
