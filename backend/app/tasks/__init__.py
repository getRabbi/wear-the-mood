"""Finite one-shot tasks (blueprint §11.6, §11.7).

Each module here is a bounded, idempotent command with a ``main()`` that exits 0 on
success / non-zero on failure and never starts its own scheduling loop — Azure
Container Apps scheduled Jobs (and, on the DO bridge, ofelia) do the scheduling.
"""
