from fastapi import APIRouter

from app.routers.v1 import (
    account,
    billing,
    calendar,
    challenges,
    consents,
    credits,
    flags,
    guide,
    health,
    me,
    news,
    notifications,
    offers,
    outfits,
    packing,
    polls,
    profile,
    quiz,
    referrals,
    shop,
    social,
    stylist,
    tryon,
    tryon_photos,
    wardrobe,
)

api_router = APIRouter()
api_router.include_router(health.router)
api_router.include_router(flags.router)
api_router.include_router(me.router)
api_router.include_router(credits.router)
api_router.include_router(tryon.router)
api_router.include_router(tryon_photos.router)
api_router.include_router(wardrobe.router)
api_router.include_router(outfits.router)
api_router.include_router(account.router)
api_router.include_router(profile.router)
api_router.include_router(consents.router)
api_router.include_router(stylist.router)
api_router.include_router(social.router)
api_router.include_router(polls.router)
api_router.include_router(quiz.router)
api_router.include_router(guide.router)
api_router.include_router(offers.router)
api_router.include_router(notifications.router)
api_router.include_router(challenges.router)
api_router.include_router(news.router)
api_router.include_router(shop.router)
api_router.include_router(billing.router)
api_router.include_router(referrals.router)
api_router.include_router(packing.router)
api_router.include_router(calendar.router)
