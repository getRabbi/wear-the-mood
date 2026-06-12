"""Shop-the-look affiliate links (CLAUDE.md §18, §24).

Builds an attributed search/deep link to a retailer for a query (a trend, a
wardrobe item, an outfit piece). The affiliate program is config-driven and
backend-only (§11) so it can be swapped without an app update; until the founder
sets one, links point at a neutral web search (no attribution).
"""

from __future__ import annotations

from urllib.parse import urlencode

from pydantic import BaseModel


class ShopLink(BaseModel):
    """A shoppable link the app opens (and logs as affiliate_link_clicked, §15)."""

    url: str
    label: str
    query: str


class ShopLinkBuilder:
    """Builds a search URL from a query, appending the affiliate tag when set."""

    def __init__(
        self,
        *,
        name: str,
        search_url: str,
        query_param: str = "q",
        tag_param: str = "",
        tag: str = "",
    ) -> None:
        self.name = name
        self._search_url = search_url
        self._query_param = query_param
        self._tag_param = tag_param
        self._tag = tag

    def build(self, query: str, *, label: str) -> ShopLink:
        params = {self._query_param: query}
        if self._tag_param and self._tag:  # attach attribution only when configured
            params[self._tag_param] = self._tag
        url = f"{self._search_url}?{urlencode(params)}"
        return ShopLink(url=url, label=label, query=query)
