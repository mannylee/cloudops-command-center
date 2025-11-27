"""
Property-based tests for event helper functions
"""

import math
from hypothesis import given, strategies as st
from event_helpers import create_account_batches


# Property Test 1: Batch count calculation
# Feature: bedrock-analysis-optimization, Property 3: Correct batch count calculation
# Validates: Requirements 2.1, 2.2
@given(
    accounts=st.lists(st.text(min_size=12, max_size=12), min_size=0, max_size=200),
    batch_size=st.integers(min_value=1, max_value=20)
)
def test_batch_count_calculation(accounts, batch_size):
    """
    For any list of accounts and batch size, the number of batches created
    should equal ceil(len(accounts) / batch_size).
    """
    batches = create_account_batches(accounts, batch_size)
    
    if len(accounts) == 0:
        assert len(batches) == 0, "Empty account list should produce zero batches"
    else:
        expected_batch_count = math.ceil(len(accounts) / batch_size)
        assert len(batches) == expected_batch_count, (
            f"Expected {expected_batch_count} batches for {len(accounts)} accounts "
            f"with batch size {batch_size}, got {len(batches)}"
        )


# Property Test 2: All accounts included
@given(
    accounts=st.lists(st.text(min_size=12, max_size=12), min_size=0, max_size=200),
    batch_size=st.integers(min_value=1, max_value=20)
)
def test_all_accounts_included(accounts, batch_size):
    """
    For any list of accounts, all accounts should appear exactly once
    across all batches (no duplicates, no missing accounts).
    """
    batches = create_account_batches(accounts, batch_size)
    
    # Flatten all batches
    flattened = [account for batch in batches for account in batch]
    
    # Check all accounts are included
    assert sorted(flattened) == sorted(accounts), (
        "All accounts should be included exactly once across all batches"
    )


# Property Test 3: Batch size constraint
@given(
    accounts=st.lists(st.text(min_size=12, max_size=12), min_size=1, max_size=200),
    batch_size=st.integers(min_value=1, max_value=20)
)
def test_batch_size_constraint(accounts, batch_size):
    """
    For any list of accounts, each batch should contain at most batch_size accounts,
    except possibly the last batch which may contain fewer.
    """
    batches = create_account_batches(accounts, batch_size)
    
    for i, batch in enumerate(batches):
        if i < len(batches) - 1:
            # All batches except the last should be exactly batch_size
            assert len(batch) == batch_size, (
                f"Batch {i} should contain exactly {batch_size} accounts, "
                f"got {len(batch)}"
            )
        else:
            # Last batch should be at most batch_size
            assert len(batch) <= batch_size, (
                f"Last batch should contain at most {batch_size} accounts, "
                f"got {len(batch)}"
            )


if __name__ == "__main__":
    # Run tests with 100 iterations each
    test_batch_count_calculation()
    test_all_accounts_included()
    test_batch_size_constraint()
    print("All property tests passed!")
