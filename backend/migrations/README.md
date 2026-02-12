"""Initialize Alembic migrations.

This file is for documentation purposes.
To initialize Alembic in your project, run from backend folder:

    alembic init migrations

Then configure alembic/env.py to:
1. Import your models
2. Set sqlalchemy.url in alembic.ini
3. Set target_metadata = Base.metadata

To create first migration:
    alembic revision --autogenerate -m "Initial migration"

To apply migrations:
    alembic upgrade head
"""
