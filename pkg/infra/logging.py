import logging
import logging.handlers
import os
import sys
from pathlib import Path
from typing import Any

import structlog
from structlog.stdlib import LoggerFactory

from pkg.infra.settings import get_settings


def setup_logging():
    settings = get_settings()
    
    # Setup handlers
    handlers = []
    
    # Console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(getattr(logging, settings.log_level))
    handlers.append(console_handler)
    
    # File handler with rotation (if log directory is specified)
    log_dir = os.environ.get("LOG_DIR", "./logs")
    if log_dir and settings.app_env == "prod":
        Path(log_dir).mkdir(parents=True, exist_ok=True)
        log_file = os.path.join(log_dir, f"{settings.app_name}.log")
        
        # Rotating file handler - 10MB per file, keep 7 days
        file_handler = logging.handlers.RotatingFileHandler(
            filename=log_file,
            maxBytes=10 * 1024 * 1024,  # 10MB
            backupCount=7,  # Keep 7 backup files
            encoding="utf-8",
        )
        file_handler.setLevel(getattr(logging, settings.log_level))
        handlers.append(file_handler)
    
    # Configure logging
    logging.basicConfig(
        format="%(message)s",
        level=getattr(logging, settings.log_level),
        handlers=handlers,
    )
    
    # Configure structlog based on environment
    renderers = [
        structlog.processors.JSONRenderer()
    ] if settings.app_env == "prod" else [
        structlog.dev.ConsoleRenderer()
    ]
    
    structlog.configure(
        processors=[
            structlog.stdlib.filter_by_level,
            structlog.stdlib.add_logger_name,
            structlog.stdlib.add_log_level,
            structlog.stdlib.PositionalArgumentsFormatter(),
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.UnicodeDecoder(),
            *renderers,
        ],
        context_class=dict,
        logger_factory=LoggerFactory(),
        cache_logger_on_first_use=True,
    )


def get_logger(name: str) -> Any:
    return structlog.get_logger(name)