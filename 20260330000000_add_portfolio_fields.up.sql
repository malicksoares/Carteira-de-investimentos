use axum::{
    Json, Router,
    extract::Path,
    http::StatusCode,
    routing::{get, patch},
};
use serde::Deserialize;

use crate::{
    app::AppState, auth::user::User, error::AppError, models::Asset, repository::Repository,
};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/assets", get(list_assets).post(create_asset))
        .route("/assets/{id}", patch(update_asset).delete(delete_asset))
}

#[tracing::instrument(skip_all)]
async fn list_assets(user: User, repository: Repository) -> Result<Json<Vec<Asset>>, AppError> {
    let assets = repository.list_assets(user.id()).await?;
    Ok(Json(assets))
}

#[derive(Deserialize)]
struct CreateAssetRequest {
    name: String,
    #[serde(default = "default_category")]
    category: String,
    #[serde(default = "default_quantity")]
    quantity: f64,
    unit_value: f64,
}

fn default_category() -> String {
    "Outros".to_string()
}

fn default_quantity() -> f64 {
    1.0
}

fn validate_asset_input(name: &str, quantity: f64, unit_value: f64) -> Result<(), AppError> {
    if name.trim().is_empty() {
        return Err(AppError::Validation(
            "O nome do ativo é obrigatório".to_string(),
        ));
    }
    if quantity < 0.0 {
        return Err(AppError::Validation(
            "A quantidade não pode ser negativa".to_string(),
        ));
    }
    if unit_value < 0.0 {
        return Err(AppError::Validation(
            "O valor unitário não pode ser negativo".to_string(),
        ));
    }
    Ok(())
}

#[tracing::instrument(skip_all)]
async fn create_asset(
    user: User,
    repository: Repository,
    Json(request): Json<CreateAssetRequest>,
) -> Result<Json<Asset>, AppError> {
    validate_asset_input(&request.name, request.quantity, request.unit_value)?;

    let new_asset = repository
        .create_asset(
            user.id(),
            request.name,
            request.category,
            request.quantity,
            request.unit_value,
        )
        .await
        .map_err(|err| match err {
            sqlx::Error::Database(db_err) if db_err.is_unique_violation() => {
                AppError::Validation("Você já possui um ativo com esse nome".to_string())
            }
            other => AppError::Database(other),
        })?;

    Ok(Json(new_asset))
}

#[derive(Deserialize)]
struct UpdateAssetRequest {
    name: Option<String>,
    category: Option<String>,
    quantity: Option<f64>,
    unit_value: Option<f64>,
}

#[tracing::instrument(skip_all)]
async fn update_asset(
    user: User,
    repository: Repository,
    Path(id): Path<i64>,
    Json(request): Json<UpdateAssetRequest>,
) -> Result<Json<Asset>, AppError> {
    if request.quantity.is_some_and(|quantity| quantity < 0.0) {
        return Err(AppError::Validation(
            "A quantidade não pode ser negativa".to_string(),
        ));
    }
    if request.unit_value.is_some_and(|unit_value| unit_value < 0.0) {
        return Err(AppError::Validation(
            "O valor unitário não pode ser negativo".to_string(),
        ));
    }

    match repository
        .update_asset(
            user.id(),
            id,
            request.name,
            request.category,
            request.quantity,
            request.unit_value,
        )
        .await?
    {
        Some(updated_asset) => Ok(Json(updated_asset)),
        None => Err(AppError::AssetDoesNotExist),
    }
}

#[tracing::instrument(skip_all)]
async fn delete_asset(
    user: User,
    repository: Repository,
    Path(id): Path<i64>,
) -> Result<StatusCode, AppError> {
    let deleted = repository.delete_asset(user.id(), id).await?;

    if deleted {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(AppError::AssetDoesNotExist)
    }
}

#[cfg(test)]
mod tests {
    use sqlx::PgPool;

    use super::*;
    use crate::auth::user::User;

    fn test_user() -> User {
        User::new(1, "trader".to_string())
    }

    #[sqlx::test(fixtures("users_and_assets"))]
    async fn test_list_assets(db: PgPool) {
        let Json(assets) = list_assets(test_user(), db.into()).await.expect("success");

        assert_eq!(assets.len(), 1);
        assert_eq!(assets[0].name, "Bitcoin");
        assert_eq!(assets[0].quantity, 2.0);

        insta::assert_json_snapshot!(assets);
    }

    #[sqlx::test(fixtures("users_and_assets"))]
    async fn test_create_asset(db: PgPool) {
        let request = CreateAssetRequest {
            name: "Ethereum".to_string(),
            category: "Cripto".to_string(),
            quantity: 5.0,
            unit_value: 20.0,
        };

        let Json(new_asset) = create_asset(test_user(), db.into(), Json(request))
            .await
            .expect("success");

        assert_eq!(new_asset.name, "Ethereum");
        assert_eq!(new_asset.category, "Cripto");
        assert_eq!(new_asset.quantity, 5.0);
        assert_eq!(new_asset.unit_value, 20.0);
        assert_eq!(new_asset.total_value(), 100.0);

        insta::assert_json_snapshot!(new_asset);
    }

    #[sqlx::test(fixtures("users_and_assets"))]
    async fn test_create_asset_rejects_negative_quantity(db: PgPool) {
        let request = CreateAssetRequest {
            name: "Ação XPTO".to_string(),
            category: "Ações".to_string(),
            quantity: -1.0,
            unit_value: 10.0,
        };

        let result = create_asset(test_user(), db.into(), Json(request)).await;

        assert!(matches!(result, Err(AppError::Validation(_))));
    }

    #[sqlx::test(fixtures("users_and_assets"))]
    async fn test_update_asset(db: PgPool) {
        let request = UpdateAssetRequest {
            name: Some("Bitcoin Atualizado".to_string()),
            category: None,
            quantity: Some(3.0),
            unit_value: Some(30.0),
        };

        let Json(updated_asset) = update_asset(test_user(), db.into(), Path(1), Json(request))
            .await
            .expect("success");

        assert_eq!(updated_asset.name, "Bitcoin Atualizado");
        assert_eq!(updated_asset.quantity, 3.0);
        assert_eq!(updated_asset.unit_value, 30.0);

        insta::assert_json_snapshot!(updated_asset);
    }

    #[sqlx::test(fixtures("users_and_assets"))]
    async fn test_update_asset_not_found(db: PgPool) {
        let request = UpdateAssetRequest {
            name: None,
            category: None,
            quantity: None,
            unit_value: Some(1.0),
        };

        let result = update_asset(test_user(), db.into(), Path(999), Json(request)).await;

        assert!(matches!(result, Err(AppError::AssetDoesNotExist)));
    }

    #[sqlx::test(fixtures("users_and_assets"))]
    async fn test_delete_asset(db: PgPool) {
        let status = delete_asset(test_user(), db.into(), Path(1))
            .await
            .expect("success");

        assert_eq!(status, StatusCode::NO_CONTENT);
    }
}
