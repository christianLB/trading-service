"""Initial migration with CONTRACT-FIRST models

Revision ID: 7af358d07c2f
Revises: 
Create Date: 2025-08-21 17:59:12.737408

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '7af358d07c2f'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create all tables following CONTRACT-FIRST approach from OpenAPI schemas."""
    
    # Create orders table (from OpenAPI OrderResponse schema)
    op.create_table(
        'orders',
        sa.Column('id', sa.String(), nullable=False),
        sa.Column('symbol', sa.String(), nullable=False),
        sa.Column('side', sa.Enum('BUY', 'SELL', name='orderside'), nullable=False),
        sa.Column('type', sa.Enum('MARKET', 'LIMIT', name='ordertype'), nullable=False),
        sa.Column('qty', sa.Float(), nullable=False),
        sa.Column('limit_price', sa.Float(), nullable=True),
        sa.Column('filled_qty', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('avg_price', sa.Float(), nullable=True),
        sa.Column('status', sa.Enum('ACCEPTED', 'PENDING', 'FILLED', 'REJECTED', 'CANCELLED', name='orderstatus'), nullable=False),
        sa.Column('client_id', sa.String(), nullable=False),
        sa.Column('idempotency_key', sa.String(), nullable=False),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_orders_idempotency_key'), 'orders', ['idempotency_key'], unique=True)
    op.create_index(op.f('ix_orders_symbol'), 'orders', ['symbol'], unique=False)
    
    # Create fills table (for webhook order_filled events)
    op.create_table(
        'fills',
        sa.Column('id', sa.String(), nullable=False),
        sa.Column('order_id', sa.String(), nullable=False),
        sa.Column('symbol', sa.String(), nullable=False),
        sa.Column('side', sa.Enum('BUY', 'SELL', name='orderside'), nullable=False),
        sa.Column('qty', sa.Float(), nullable=False),
        sa.Column('price', sa.Float(), nullable=False),
        sa.Column('client_id', sa.String(), nullable=False),
        sa.Column('timestamp', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_fills_order_id'), 'fills', ['order_id'], unique=False)
    
    # Create positions table (from OpenAPI PositionResponse schema)
    op.create_table(
        'positions',
        sa.Column('symbol', sa.String(), nullable=False),
        sa.Column('qty', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('avg_price', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('notional', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('pnl', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('symbol')
    )
    
    # Create risk_metrics table (for risk management)
    op.create_table(
        'risk_metrics',
        sa.Column('date', sa.String(), nullable=False),
        sa.Column('daily_loss_usd', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('total_position_usd', sa.Float(), nullable=False, server_default='0.0'),
        sa.Column('risk_blocks_count', sa.Float(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('date')
    )
    
    # Create webhook_logs table (for webhook delivery tracking)
    op.create_table(
        'webhook_logs',
        sa.Column('id', sa.String(), nullable=False),
        sa.Column('event', sa.String(), nullable=False),
        sa.Column('url', sa.String(), nullable=False),
        sa.Column('payload', sa.Text(), nullable=False),
        sa.Column('signature', sa.String(), nullable=False),
        sa.Column('status_code', sa.Float(), nullable=True),
        sa.Column('response', sa.Text(), nullable=True),
        sa.Column('retry_count', sa.Float(), nullable=False, server_default='0'),
        sa.Column('created_at', sa.DateTime(), server_default=sa.text('now()'), nullable=False),
        sa.PrimaryKeyConstraint('id')
    )


def downgrade() -> None:
    """Drop all tables."""
    op.drop_table('webhook_logs')
    op.drop_table('risk_metrics')
    op.drop_table('positions')
    op.drop_index(op.f('ix_fills_order_id'), table_name='fills')
    op.drop_table('fills')
    op.drop_index(op.f('ix_orders_symbol'), table_name='orders')
    op.drop_index(op.f('ix_orders_idempotency_key'), table_name='orders')
    op.drop_table('orders')
    
    # Drop enums
    op.execute('DROP TYPE IF EXISTS orderstatus')
    op.execute('DROP TYPE IF EXISTS ordertype')
    op.execute('DROP TYPE IF EXISTS orderside')
