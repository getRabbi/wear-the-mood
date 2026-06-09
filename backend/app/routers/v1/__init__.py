from fastapi import APIRouter

from app.routers.v1 import credits, health, me, tryon

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(me.router)
api_router.include_router(credits.router)
api_router.include_router(tryon.router)
