use std::convert::Infallible;

use axum::extract::FromRequestParts;
use axum_extra::extract::CookieJar;
use jwt_simple::{
    claims::Claims,
    prelude::{Duration, HS256Key, MACLike},
};
use password_auth::VerifyError;
use serde::{Deserialize, Serialize};

use crate::{app::AppState, error::AppError, repository::Repository};

/// Lê a chave de assinatura do JWT da variável de ambiente `JWT_SECRET`.
/// Caso não esteja definida, cai para uma chave de desenvolvimento (nunca
/// use o valor padrão em produção).
fn secret_key() -> HS256Key {
    let secret = std::env::var("JWT_SECRET").unwrap_or_else(|_| {
        tracing::warn!(
            "JWT_SECRET não definido: usando chave de desenvolvimento. \
             Defina JWT_SECRET em produção."
        );
        "dev-only-secret-change-me".to_string()
    });

    HS256Key::from_bytes(secret.as_bytes())
}

pub struct UnauthenticatedUser {
    username: String,
    password: String,
}

impl UnauthenticatedUser {
    pub fn new(username: String, password: String) -> Self {
        Self { username, password }
    }

    pub async fn authenticate(&self, repository: &Repository) -> Result<User, AppError> {
        let user_record = match repository.get_user_by_name(&self.username).await? {
            Some(user_record) => user_record,
            None => return Err(AppError::UserDoesNotExist),
        };

        match password_auth::verify_password(&self.password, &user_record.password_hash) {
            Ok(()) => Ok(User::new(user_record.id, user_record.username)),
            Err(VerifyError::PasswordInvalid) => Err(AppError::InvalidCredentials),
            Err(VerifyError::Parse(err)) => panic!("Hashing algorithm failed: {err}"),
        }
    }

    pub async fn register(self, repository: &Repository) -> Result<User, AppError> {
        let password_hash = password_auth::generate_hash(self.password);
        let user_record = match repository.add_user(&self.username, &password_hash).await {
            Ok(user_record) => user_record,
            Err(sqlx::Error::Database(db_err)) if db_err.is_unique_violation() => {
                return Err(AppError::UsernameTaken);
            }
            Err(err) => return Err(AppError::Database(err)),
        };

        Ok(User::new(user_record.id, user_record.username))
    }
}

pub struct User {
    id: i64,
    username: String,
}

impl User {
    pub(crate) fn new(id: i64, username: String) -> Self {
        Self { id, username }
    }

    pub const fn username(&self) -> &String {
        &self.username
    }

    pub const fn id(&self) -> i64 {
        self.id
    }

    pub fn auth_token(self) -> Result<String, AppError> {
        let key = secret_key();
        // Sessão válida por 2 horas: tempo suficiente para uso normal do
        // dashboard sem comprometer a segurança de um token de vida longa.
        let claims = Claims::with_custom_claims(UserClaims::from(self), Duration::from_hours(2));
        let token = key.authenticate(claims)?;
        Ok(token)
    }

    pub fn from_auth_token(token: &str) -> Result<Self, AppError> {
        let key = secret_key();
        let claims: UserClaims = key.verify_token(token, None)?.custom;
        Ok(Self::new(claims.id, claims.username))
    }
}

impl FromRequestParts<AppState> for User {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut axum::http::request::Parts,
        _state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let jar = CookieJar::from_headers(&parts.headers);

        let token = match jar.get("token") {
            Some(token) => token.value(),
            None => return Err(AppError::MissingAuthorization),
        };

        User::from_auth_token(token)
    }
}

impl FromRequestParts<AppState> for Option<User> {
    type Rejection = Infallible;

    async fn from_request_parts(
        parts: &mut axum::http::request::Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        Ok(User::from_request_parts(parts, state).await.ok())
    }
}

#[derive(Serialize, Deserialize)]
struct UserClaims {
    id: i64,
    username: String,
}

impl From<User> for UserClaims {
    fn from(User { id, username }: User) -> Self {
        Self { id, username }
    }
}
