"""Affiliate network connectors.

A network account is a different thing from a merchant feed: one set of
credentials gives access to many advertisers, each with many feeds, and the set
changes over time as programmes are joined and left. So the shape is:

    credentials -> discover advertisers -> discover their feeds
                -> an operator enables one -> the existing sync imports it

Only the last step is shared with a directly-configured merchant, and that is
deliberate: everything downstream of "here are some records" is the catalog
importer that already exists and is already proven.
"""

from app.services.catalog.networks.awin import (
    AwinClient,
    AwinCredentialsMissing,
    AwinDiscovery,
    AwinFeed,
    AwinMultiFeedSource,
    redact,
)

__all__ = [
    "AwinClient",
    "AwinCredentialsMissing",
    "AwinDiscovery",
    "AwinFeed",
    "AwinMultiFeedSource",
    "redact",
]
