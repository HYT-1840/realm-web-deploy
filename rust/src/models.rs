
use serde::{Deserialize, Serialize};
use chrono::NaiveDateTime;

// 用户模型（对应realm_users表）
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct User {
    pub id: i32,
    pub username: String,
    pub password: String,
    pub role: String, // super_admin/admin/user
    pub create_time: Option<NaiveDateTime>,
}

// 规则模型（对应realm_rules表）
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Rule {
    pub id: i32,
    pub username: String,
    pub local_port: i32,
    pub target: String,
    pub remark: Option<String>,
    pub pid: i32,
    pub status: String, // run/stop
    pub create_time: Option<NaiveDateTime>,
}

// 新增规则请求体（API入参）
#[derive(Debug, Deserialize, Serialize)]
pub struct AddRuleRequest {
    pub local_port: String,
    pub target: String,
    pub remark: Option<String>,
}

// 通用API返回格式（与原Python一致：code/msg/data）
#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ApiResponse<T = ()> {
    pub code: i32,
    pub msg: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<T>,
}

impl ApiResponse<()> {
    // 成功响应（无数据）
    pub fn success(msg: &str) -> Self {
        Self {
            code: 0,
            msg: msg.to_string(),
            data: None,
        }
    }

    // 成功响应（带数据）
    pub fn success_with_data<T: Serialize>(data: T, msg: &str) -> ApiResponse<T> {
        ApiResponse {
            code: 0,
            msg: msg.to_string(),
            data: Some(data),
        }
    }

    // 失败响应
    pub fn error(msg: &str) -> Self {
        Self {
            code: 1,
            msg: msg.to_string(),
            data: None,
        }
    }
}
