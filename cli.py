#!/usr/bin/env python3
"""
Trading Service CLI Management Tool

A command-line interface for managing the Trading Service.
"""
import asyncio
import json
import os
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

import httpx
import typer
from rich import print as rprint
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent))

from pkg.infra.settings import Settings

app = typer.Typer(
    name="trading-cli",
    help="Trading Service management CLI",
    add_completion=True,
)
console = Console()

# Subcommands
order_app = typer.Typer(help="Order management commands")
position_app = typer.Typer(help="Position management commands")
health_app = typer.Typer(help="Health and monitoring commands")
backup_app = typer.Typer(help="Backup and restore commands")

app.add_typer(order_app, name="order")
app.add_typer(position_app, name="position")
app.add_typer(health_app, name="health")
app.add_typer(backup_app, name="backup")


def get_api_url() -> str:
    """Get API URL from environment or default."""
    return os.getenv("API_URL", "http://localhost:8085")


def get_api_token() -> str:
    """Get API token from environment or default."""
    return os.getenv("API_TOKEN", "change_me")


async def make_request(
    method: str,
    endpoint: str,
    json_data: Optional[dict] = None,
    params: Optional[dict] = None,
) -> httpx.Response:
    """Make HTTP request to the API."""
    url = f"{get_api_url()}{endpoint}"
    headers = {"Authorization": f"Bearer {get_api_token()}"}
    
    async with httpx.AsyncClient() as client:
        response = await client.request(
            method=method,
            url=url,
            headers=headers,
            json=json_data,
            params=params,
            timeout=10.0,
        )
    
    return response


# Order Commands
@order_app.command("create")
def create_order(
    symbol: str = typer.Argument(..., help="Trading symbol (e.g., BTC/USDT)"),
    side: str = typer.Argument(..., help="Order side (buy/sell)"),
    order_type: str = typer.Argument("market", help="Order type (market/limit)"),
    qty: float = typer.Argument(..., help="Order quantity"),
    limit_price: Optional[float] = typer.Option(None, help="Limit price for limit orders"),
    client_id: str = typer.Option("cli", help="Client identifier"),
):
    """Create a new order."""
    async def _create():
        order_data = {
            "symbol": symbol,
            "side": side,
            "type": order_type,
            "qty": qty,
            "clientId": client_id,
            "idempotencyKey": f"cli-{datetime.now().isoformat()}",
        }
        
        if limit_price and order_type == "limit":
            order_data["limitPrice"] = limit_price
        
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            console=console,
        ) as progress:
            progress.add_task("Creating order...", total=None)
            
            try:
                response = await make_request("POST", "/orders", json_data=order_data)
                response.raise_for_status()
                
                result = response.json()
                console.print(Panel(
                    f"[green]✓ Order created successfully![/green]\n\n"
                    f"Order ID: {result['orderId']}\n"
                    f"Status: {result['status']}",
                    title="Order Created",
                    border_style="green",
                ))
            except httpx.HTTPStatusError as e:
                if e.response.status_code == 422:
                    error_detail = e.response.json().get("detail", "Unknown error")
                    console.print(f"[red]✗ Risk blocked: {error_detail}[/red]")
                else:
                    console.print(f"[red]✗ Error: {e.response.text}[/red]")
            except Exception as e:
                console.print(f"[red]✗ Error: {str(e)}[/red]")
    
    asyncio.run(_create())


@order_app.command("get")
def get_order(order_id: str = typer.Argument(..., help="Order ID")):
    """Get order details by ID."""
    async def _get():
        try:
            response = await make_request("GET", f"/orders/{order_id}")
            response.raise_for_status()
            
            order = response.json()
            
            table = Table(title=f"Order {order_id}", show_header=False)
            table.add_column("Field", style="cyan")
            table.add_column("Value", style="white")
            
            for key, value in order.items():
                if isinstance(value, float):
                    value = f"{value:.8f}".rstrip("0").rstrip(".")
                table.add_row(key.replace("_", " ").title(), str(value))
            
            console.print(table)
        except httpx.HTTPStatusError as e:
            if e.response.status_code == 404:
                console.print(f"[red]✗ Order {order_id} not found[/red]")
            else:
                console.print(f"[red]✗ Error: {e.response.text}[/red]")
        except Exception as e:
            console.print(f"[red]✗ Error: {str(e)}[/red]")
    
    asyncio.run(_get())


@order_app.command("list")
def list_orders(
    limit: int = typer.Option(10, help="Number of orders to show"),
    status: Optional[str] = typer.Option(None, help="Filter by status"),
):
    """List recent orders."""
    console.print("[yellow]Note: Order listing endpoint not yet implemented[/yellow]")
    console.print("This will show recent orders once the API endpoint is available.")


# Position Commands
@position_app.command("list")
def list_positions():
    """List all current positions."""
    async def _list():
        try:
            response = await make_request("GET", "/positions")
            response.raise_for_status()
            
            data = response.json()
            positions = data.get("positions", [])
            
            if not positions:
                console.print("[yellow]No open positions[/yellow]")
                return
            
            table = Table(title="Current Positions")
            table.add_column("Symbol", style="cyan")
            table.add_column("Quantity", justify="right")
            table.add_column("Avg Price", justify="right")
            table.add_column("Notional", justify="right")
            table.add_column("P&L", justify="right")
            
            for pos in positions:
                pnl = pos.get("unrealized_pnl", 0)
                pnl_color = "green" if pnl >= 0 else "red"
                
                table.add_row(
                    pos["symbol"],
                    f"{pos['qty']:.8f}".rstrip("0").rstrip("."),
                    f"${pos['avg_price']:.2f}",
                    f"${pos['notional']:.2f}",
                    f"[{pnl_color}]${pnl:.2f}[/{pnl_color}]",
                )
            
            console.print(table)
            
            # Show total notional
            total_notional = sum(p.get("notional", 0) for p in positions)
            console.print(f"\n[bold]Total Notional: ${total_notional:.2f}[/bold]")
            
        except Exception as e:
            console.print(f"[red]✗ Error: {str(e)}[/red]")
    
    asyncio.run(_list())


@position_app.command("close")
def close_position(
    symbol: str = typer.Argument(..., help="Symbol to close (e.g., BTC/USDT)"),
    confirm: bool = typer.Option(False, "--yes", "-y", help="Skip confirmation"),
):
    """Close a position by creating an offsetting order."""
    console.print("[yellow]Note: Position closing requires manual order creation[/yellow]")
    console.print(f"To close {symbol}, create a sell order for the position quantity.")


# Health Commands
@health_app.command("check")
def health_check(verbose: bool = typer.Option(False, "--verbose", "-v")):
    """Check service health status."""
    async def _check():
        try:
            with Progress(
                SpinnerColumn(),
                TextColumn("[progress.description]{task.description}"),
                console=console,
            ) as progress:
                progress.add_task("Checking health...", total=None)
                
                response = await make_request("GET", "/healthz")
                response.raise_for_status()
                
            health = response.json()
            
            # Determine overall status
            status = health.get("status", "unknown")
            status_color = {
                "healthy": "green",
                "degraded": "yellow",
                "unhealthy": "red",
            }.get(status, "white")
            
            # Create status panel
            panel_content = f"[{status_color}]● {status.upper()}[/{status_color}]\n\n"
            panel_content += f"Database: {health.get('database', 'unknown')}\n"
            panel_content += f"Redis: {health.get('redis', 'unknown')}\n"
            panel_content += f"Timestamp: {health.get('timestamp', 'N/A')}"
            
            console.print(Panel(
                panel_content,
                title="Service Health",
                border_style=status_color,
            ))
            
            if verbose:
                console.print("\n[dim]Raw response:[/dim]")
                console.print(json.dumps(health, indent=2))
                
        except Exception as e:
            console.print(f"[red]✗ Service unavailable: {str(e)}[/red]")
    
    asyncio.run(_check())


@health_app.command("metrics")
def show_metrics():
    """Display Prometheus metrics."""
    async def _metrics():
        try:
            response = await make_request("GET", "/metrics")
            response.raise_for_status()
            
            metrics_text = response.text
            
            # Parse key metrics
            orders_total = 0
            fills_total = 0
            risk_blocks = 0
            
            for line in metrics_text.split("\n"):
                if line.startswith("orders_total"):
                    orders_total = int(float(line.split()[-1]))
                elif line.startswith("fills_total"):
                    fills_total = int(float(line.split()[-1]))
                elif line.startswith("risk_blocks_total"):
                    risk_blocks = int(float(line.split()[-1]))
            
            table = Table(title="Service Metrics")
            table.add_column("Metric", style="cyan")
            table.add_column("Value", justify="right")
            
            table.add_row("Total Orders", str(orders_total))
            table.add_row("Total Fills", str(fills_total))
            table.add_row("Risk Blocks", str(risk_blocks))
            
            console.print(table)
            
        except Exception as e:
            console.print(f"[red]✗ Error: {str(e)}[/red]")
    
    asyncio.run(_metrics())


# Backup Commands
@backup_app.command("create")
def create_backup(
    environment: str = typer.Option("dev", help="Environment (dev/prod)"),
):
    """Create a database backup."""
    if environment == "dev":
        os.system("make dev-backup")
    else:
        console.print("[yellow]For production backup, use: make nas-backup[/yellow]")


@backup_app.command("list")
def list_backups():
    """List available backups."""
    backup_dir = Path("./backups")
    if not backup_dir.exists():
        console.print("[yellow]No backups directory found[/yellow]")
        return
    
    backups = sorted(backup_dir.glob("*.sql.gz"), reverse=True)
    
    if not backups:
        console.print("[yellow]No backups found[/yellow]")
        return
    
    table = Table(title="Available Backups")
    table.add_column("Filename", style="cyan")
    table.add_column("Size", justify="right")
    table.add_column("Modified", justify="right")
    
    for backup in backups[:10]:  # Show last 10
        size = backup.stat().st_size / 1024  # KB
        mtime = datetime.fromtimestamp(backup.stat().st_mtime)
        
        table.add_row(
            backup.name,
            f"{size:.1f} KB",
            mtime.strftime("%Y-%m-%d %H:%M"),
        )
    
    console.print(table)


# Main Commands
@app.command()
def config(
    show: bool = typer.Option(True, help="Show current configuration"),
    set_url: Optional[str] = typer.Option(None, "--url", help="Set API URL"),
    set_token: Optional[str] = typer.Option(None, "--token", help="Set API token"),
):
    """Show or update CLI configuration."""
    if set_url or set_token:
        console.print("[yellow]Note: Set environment variables instead:[/yellow]")
        if set_url:
            console.print(f"export API_URL={set_url}")
        if set_token:
            console.print(f"export API_TOKEN={set_token}")
    
    if show:
        table = Table(title="Current Configuration", show_header=False)
        table.add_column("Setting", style="cyan")
        table.add_column("Value", style="white")
        
        table.add_row("API URL", get_api_url())
        table.add_row("API Token", f"{get_api_token()[:8]}..." if len(get_api_token()) > 8 else get_api_token())
        
        console.print(table)


@app.command()
def status():
    """Show overall system status."""
    async def _status():
        console.print(Panel("[bold]Trading Service Status[/bold]", style="blue"))
        
        # Check health
        try:
            response = await make_request("GET", "/healthz")
            health = response.json()
            status = health.get("status", "unknown")
            
            status_icon = {
                "healthy": "✓",
                "degraded": "⚠",
                "unhealthy": "✗",
            }.get(status, "?")
            
            status_color = {
                "healthy": "green",
                "degraded": "yellow",
                "unhealthy": "red",
            }.get(status, "white")
            
            console.print(f"Health: [{status_color}]{status_icon} {status}[/{status_color}]")
            
            # Get metrics
            response = await make_request("GET", "/metrics")
            metrics_text = response.text
            
            orders_total = 0
            for line in metrics_text.split("\n"):
                if line.startswith("orders_total"):
                    orders_total = int(float(line.split()[-1]))
                    break
            
            console.print(f"Total Orders: {orders_total}")
            
            # Get positions
            response = await make_request("GET", "/positions")
            positions = response.json().get("positions", [])
            
            console.print(f"Open Positions: {len(positions)}")
            
            if positions:
                total_notional = sum(p.get("notional", 0) for p in positions)
                console.print(f"Total Notional: ${total_notional:.2f}")
            
        except Exception as e:
            console.print(f"[red]✗ Service unavailable: {str(e)}[/red]")
    
    asyncio.run(_status())


@app.command()
def version():
    """Show CLI and service version."""
    console.print("[bold]Trading Service CLI[/bold]")
    console.print("Version: 0.1.0")
    console.print(f"API URL: {get_api_url()}")


if __name__ == "__main__":
    app()