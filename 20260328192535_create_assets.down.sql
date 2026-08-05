use askama::Template;
use axum::{
    Form, Router,
    extract::Path,
    response::{Html, IntoResponse, Redirect, Response},
    routing::{get, post},
};
use axum_extra::extract::{CookieJar, cookie::Cookie, cookie::SameSite};
use serde::Deserialize;

use crate::{
    app::AppState,
    auth::user::{UnauthenticatedUser, User},
    error::AppError,
    models::Asset,
    repository::Repository,
};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/", get(dashboard))
        .route("/login", get(login_page).post(login))
        .route("/register", get(register_page).post(register))
        .route("/logout", get(logout))
        .route("/assets/new", get(new_asset_page).post(create_asset_form))
        .route(
            "/assets/{id}/edit",
            get(edit_asset_page).post(update_asset_form),
        )
        .route("/assets/{id}/delete", post(delete_asset_form))
}

fn auth_cookie(token: String) -> Cookie<'static> {
    Cookie::build(("token", token))
        .http_only(true)
        .path("/")
        .same_site(SameSite::Lax)
        .into()
}

fn format_money(value: f64) -> String {
    format!("{value:.2}")
}

// ---------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------

struct AssetView {
    id: i64,
    name: String,
    category: String,
    quantity_display: String,
    unit_value_display: String,
    total_value_display: String,
}

impl From<Asset> for AssetView {
    fn from(asset: Asset) -> Self {
        let total = asset.total_value();
        Self {
            id: asset.id,
            name: asset.name,
            category: asset.category,
            quantity_display: format_money(asset.quantity),
            unit_value_display: format_money(asset.unit_value),
            total_value_display: format_money(total),
        }
    }
}

#[derive(Template)]
#[template(path = "dashboard.html")]
struct DashboardPage {
    username: String,
    assets: Vec<AssetView>,
    total_value_display: String,
}

async fn dashboard(maybe_user: Option<User>, repository: Repository) -> Result<Response, AppError> {
    let Some(user) = maybe_user else {
        return Ok(Redirect::to("/login").into_response());
    };

    let assets = repository.list_assets(user.id()).await?;
    let total_value: f64 = assets.iter().map(Asset::total_value).sum();
    let assets = assets.into_iter().map(AssetView::from).collect();

    let html = DashboardPage {
        username: user.username().clone(),
        assets,
        total_value_display: format_money(total_value),
    }
    .render()?;

    Ok(Html(html).into_response())
}

// ---------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------

#[derive(Template)]
#[template(path = "login.html")]
struct LoginPage {
    error: Option<String>,
}

async fn login_page() -> Result<Html<String>, AppError> {
    let html = LoginPage { error: None }.render()?;
    Ok(Html(html))
}

#[derive(Deserialize)]
struct LoginForm {
    username: String,
    password: String,
}

async fn login(
    repository: Repository,
    jar: CookieJar,
    Form(request): Form<LoginForm>,
) -> Result<Response, AppError> {
    let unauth_user = UnauthenticatedUser::new(request.username, request.password);

    let user = match unauth_user.authenticate(&repository).await {
        Ok(user) => user,
        // Não revelamos se o problema foi o usuário ou a senha.
        Err(AppError::UserDoesNotExist | AppError::InvalidCredentials) => {
            let html = LoginPage {
                error: Some("Usuário ou senha inválidos".to_string()),
            }
            .render()?;
            return Ok(Html(html).into_response());
        }
        Err(other_err) => return Err(other_err),
    };

    let token = user.auth_token()?;
    Ok((jar.add(auth_cookie(token)), Redirect::to("/")).into_response())
}

// ---------------------------------------------------------------------
// Registro
// ---------------------------------------------------------------------

#[derive(Template)]
#[template(path = "register.html")]
struct RegisterPage {
    error: Option<String>,
}

async fn register_page() -> Result<Html<String>, AppError> {
    let html = RegisterPage { error: None }.render()?;
    Ok(Html(html))
}

#[derive(Deserialize)]
struct RegisterForm {
    username: String,
    password: String,
}

fn validate_credentials(username: &str, password: &str) -> Result<(), String> {
    if username.trim().len() < 3 {
        return Err("O usuário deve ter pelo menos 3 caracteres".to_string());
    }
    if password.len() < 6 {
        return Err("A senha deve ter pelo menos 6 caracteres".to_string());
    }
    Ok(())
}

async fn register(
    repository: Repository,
    jar: CookieJar,
    Form(request): Form<RegisterForm>,
) -> Result<Response, AppError> {
    if let Err(message) = validate_credentials(&request.username, &request.password) {
        let html = RegisterPage {
            error: Some(message),
        }
        .render()?;
        return Ok(Html(html).into_response());
    }

    let unauth_user = UnauthenticatedUser::new(request.username, request.password);

    let user = match unauth_user.register(&repository).await {
        Ok(user) => user,
        Err(AppError::UsernameTaken) => {
            let html = RegisterPage {
                error: Some("Esse nome de usuário já está em uso".to_string()),
            }
            .render()?;
            return Ok(Html(html).into_response());
        }
        Err(other_err) => return Err(other_err),
    };

    let token = user.auth_token()?;
    Ok((jar.add(auth_cookie(token)), Redirect::to("/")).into_response())
}

// ---------------------------------------------------------------------
// Logout
// ---------------------------------------------------------------------

async fn logout(jar: CookieJar) -> impl IntoResponse {
    (jar.remove(Cookie::from("token")), Redirect::to("/login"))
}

// ---------------------------------------------------------------------
// Formulário de ativos (criar / editar)
// ---------------------------------------------------------------------

#[derive(Template)]
#[template(path = "asset_form.html")]
struct AssetFormPage {
    title: String,
    action: String,
    name: String,
    category: String,
    quantity: f64,
    unit_value: f64,
    error: Option<String>,
}

#[derive(Deserialize)]
struct AssetForm {
    name: String,
    category: String,
    quantity: f64,
    unit_value: f64,
}

fn validate_asset_form(form: &AssetForm) -> Result<(), String> {
    if form.name.trim().is_empty() {
        return Err("Informe o nome do ativo".to_string());
    }
    if form.quantity < 0.0 {
        return Err("A quantidade não pode ser negativa".to_string());
    }
    if form.unit_value < 0.0 {
        return Err("O valor unitário não pode ser negativo".to_string());
    }
    Ok(())
}

async fn new_asset_page(maybe_user: Option<User>) -> Result<Response, AppError> {
    if maybe_user.is_none() {
        return Ok(Redirect::to("/login").into_response());
    }

    let html = AssetFormPage {
        title: "Novo ativo".to_string(),
        action: "/assets/new".to_string(),
        name: String::new(),
        category: String::new(),
        quantity: 1.0,
        unit_value: 0.0,
        error: None,
    }
    .render()?;

    Ok(Html(html).into_response())
}

async fn create_asset_form(
    maybe_user: Option<User>,
    repository: Repository,
    Form(form): Form<AssetForm>,
) -> Result<Response, AppError> {
    let Some(user) = maybe_user else {
        return Ok(Redirect::to("/login").into_response());
    };

    if let Err(message) = validate_asset_form(&form) {
        let html = AssetFormPage {
            title: "Novo ativo".to_string(),
            action: "/assets/new".to_string(),
            name: form.name,
            category: form.category,
            quantity: form.quantity,
            unit_value: form.unit_value,
            error: Some(message),
        }
        .render()?;
        return Ok(Html(html).into_response());
    }

    let result = repository
        .create_asset(
            user.id(),
            form.name.clone(),
            form.category.clone(),
            form.quantity,
            form.unit_value,
        )
        .await;

    if let Err(sqlx::Error::Database(db_err)) = &result {
        if db_err.is_unique_violation() {
            let html = AssetFormPage {
                title: "Novo ativo".to_string(),
                action: "/assets/new".to_string(),
                name: form.name,
                category: form.category,
                quantity: form.quantity,
                unit_value: form.unit_value,
                error: Some("Você já possui um ativo com esse nome".to_string()),
            }
            .render()?;
            return Ok(Html(html).into_response());
        }
    }

    result?;

    Ok(Redirect::to("/").into_response())
}

async fn edit_asset_page(
    maybe_user: Option<User>,
    repository: Repository,
    Path(id): Path<i64>,
) -> Result<Response, AppError> {
    let Some(user) = maybe_user else {
        return Ok(Redirect::to("/login").into_response());
    };

    let asset = repository
        .get_asset(user.id(), id)
        .await?
        .ok_or(AppError::AssetDoesNotExist)?;

    let html = AssetFormPage {
        title: "Editar ativo".to_string(),
        action: format!("/assets/{id}/edit"),
        name: asset.name,
        category: asset.category,
        quantity: asset.quantity,
        unit_value: asset.unit_value,
        error: None,
    }
    .render()?;

    Ok(Html(html).into_response())
}

async fn update_asset_form(
    maybe_user: Option<User>,
    repository: Repository,
    Path(id): Path<i64>,
    Form(form): Form<AssetForm>,
) -> Result<Response, AppError> {
    let Some(user) = maybe_user else {
        return Ok(Redirect::to("/login").into_response());
    };

    if let Err(message) = validate_asset_form(&form) {
        let html = AssetFormPage {
            title: "Editar ativo".to_string(),
            action: format!("/assets/{id}/edit"),
            name: form.name,
            category: form.category,
            quantity: form.quantity,
            unit_value: form.unit_value,
            error: Some(message),
        }
        .render()?;
        return Ok(Html(html).into_response());
    }

    repository
        .update_asset(
            user.id(),
            id,
            Some(form.name),
            Some(form.category),
            Some(form.quantity),
            Some(form.unit_value),
        )
        .await?
        .ok_or(AppError::AssetDoesNotExist)?;

    Ok(Redirect::to("/").into_response())
}

async fn delete_asset_form(
    maybe_user: Option<User>,
    repository: Repository,
    Path(id): Path<i64>,
) -> Result<Response, AppError> {
    let Some(user) = maybe_user else {
        return Ok(Redirect::to("/login").into_response());
    };

    repository.delete_asset(user.id(), id).await?;

    Ok(Redirect::to("/").into_response())
}
