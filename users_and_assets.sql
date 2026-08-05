use std::convert::Infallible;

use axum::extract::FromRequestParts;
use sqlx::PgPool;

use crate::{
    app::AppState,
    models::{Asset, UserRecord},
};

pub struct Repository {
    db: PgPool,
}

impl Repository {
    /// Lista todos os ativos que pertencem à pessoa usuária informada.
    pub async fn list_assets(&self, user_id: i64) -> sqlx::Result<Vec<Asset>> {
        sqlx::query_as!(
            Asset,
            "SELECT id, user_id, name, category, quantity, unit_value
             FROM assets
             WHERE user_id = $1
             ORDER BY name;",
            user_id
        )
        .fetch_all(&self.db)
        .await
    }

    /// Busca um único ativo, garantindo que ele pertença à pessoa usuária informada.
    pub async fn get_asset(&self, user_id: i64, asset_id: i64) -> sqlx::Result<Option<Asset>> {
        sqlx::query_as!(
            Asset,
            "SELECT id, user_id, name, category, quantity, unit_value
             FROM assets
             WHERE id = $1 AND user_id = $2;",
            asset_id,
            user_id
        )
        .fetch_optional(&self.db)
        .await
    }

    pub async fn create_asset(
        &self,
        user_id: i64,
        name: String,
        category: String,
        quantity: f64,
        unit_value: f64,
    ) -> sqlx::Result<Asset> {
        sqlx::query_as!(
            Asset,
            "INSERT INTO assets (user_id, name, category, quantity, unit_value)
             VALUES ($1, $2, $3, $4, $5)
             RETURNING id, user_id, name, category, quantity, unit_value;",
            user_id,
            name,
            category,
            quantity,
            unit_value
        )
        .fetch_one(&self.db)
        .await
    }

    pub async fn update_asset(
        &self,
        user_id: i64,
        asset_id: i64,
        name: Option<String>,
        category: Option<String>,
        quantity: Option<f64>,
        unit_value: Option<f64>,
    ) -> sqlx::Result<Option<Asset>> {
        sqlx::query_as!(
            Asset,
            "UPDATE assets
             SET name=COALESCE($3, name),
                 category=COALESCE($4, category),
                 quantity=COALESCE($5, quantity),
                 unit_value=COALESCE($6, unit_value)
             WHERE id=$1 AND user_id=$2
             RETURNING id, user_id, name, category, quantity, unit_value;",
            asset_id,
            user_id,
            name,
            category,
            quantity,
            unit_value
        )
        .fetch_optional(&self.db)
        .await
    }

    /// Remove um ativo, retornando `true` se algo foi de fato apagado.
    pub async fn delete_asset(&self, user_id: i64, asset_id: i64) -> sqlx::Result<bool> {
        let result = sqlx::query!(
            "DELETE FROM assets WHERE id = $1 AND user_id = $2;",
            asset_id,
            user_id
        )
        .execute(&self.db)
        .await?;

        Ok(result.rows_affected() > 0)
    }

    pub async fn add_user(&self, username: &str, password_hash: &str) -> sqlx::Result<UserRecord> {
        sqlx::query_as!(
            UserRecord,
            "INSERT INTO users (username, password_hash)
             VALUES ($1, $2)
             RETURNING id, username, password_hash;",
            username,
            password_hash,
        )
        .fetch_one(&self.db)
        .await
    }

    pub async fn get_user_by_name(&self, username: &str) -> sqlx::Result<Option<UserRecord>> {
        sqlx::query_as!(
            UserRecord,
            "SELECT id, username, password_hash
             FROM users
             WHERE username = $1;",
            username
        )
        .fetch_optional(&self.db)
        .await
    }
}

impl FromRequestParts<AppState> for Repository {
    type Rejection = Infallible;

    async fn from_request_parts(
        _parts: &mut axum::http::request::Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        Ok(Self {
            db: state.db.clone(),
        })
    }
}

#[cfg(test)]
impl From<PgPool> for Repository {
    fn from(db: PgPool) -> Self {
        Self { db }
    }
}
