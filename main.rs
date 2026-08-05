use axum::Router;
use sqlx::PgPool;
use tokio::net::TcpListener;
use tracing::info;
use tracing_subscriber::{
    Layer, fmt::format::FmtSpan, layer::SubscriberExt, util::SubscriberInitExt,
};

use crate::routes;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
}

impl AppState {
    async fn new() -> color_eyre::Result<Self> {
        let database_url = std::env::var("DATABASE_URL")?;
        let db = PgPool::connect(&database_url).await?;

        Ok(Self { db })
    }
}

pub struct App;

impl App {
    pub async fn start() -> color_eyre::Result<()> {
        let layer = tracing_subscriber::fmt::layer()
            .with_span_events(FmtSpan::NEW)
            .boxed();

        tracing_subscriber::registry().with(layer).init();

        // Carrega variáveis de um arquivo `.env`, se existir. Em produção
        // (ex.: Docker/CI) as variáveis normalmente já vêm do ambiente, então
        // a ausência do arquivo não deve derrubar a aplicação.
        let _ = dotenvy::dotenv();

        let state = AppState::new().await?;

        let port = std::env::var("PORT").unwrap_or_else(|_| "3000".to_string());
        let listener = TcpListener::bind(format!("0.0.0.0:{port}")).await?;

        let router = Router::new()
            .nest("/api", routes::api::router())
            .merge(routes::frontend::router())
            .with_state(state);

        info!("Starting service on port {port}");

        axum::serve(listener, router).await?;

        Ok(())
    }
}
