// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IPool {
    /**
     *  @notice Returns the address of the pool's quote token.
     */
    function quoteTokenAddress() external view returns (address);

    /**
     *  @notice Returns the `quoteTokenScale` state variable.
     *  @notice Token scale is also the minimum amount a lender may have in a bucket (dust amount).
     *  @return The precision of the quote `ERC20` token based on decimals.
     */
    function quoteTokenScale() external view returns (uint256);

    /**
     *  @notice Mapping of buckets indexes and owner addresses to `Lender` structs.
     *  @param  index_       Bucket index.
     *  @param  lender_      Address of the liquidity provider.
     *  @return lpBalance_   Amount of `LP` owner has in current bucket.
     *  @return depositTime_ Time the user last deposited quote token.
     */
    function lenderInfo(
        uint256 index_,
        address lender_
    )
        external
        view
        returns (uint256 lpBalance_, uint256 depositTime_);

    /**
     *  @notice Returns the exchange rate for a given bucket index.
     *  @param  index_        The bucket index.
     *  @return exchangeRate_ Exchange rate of the bucket (`WAD` precision).
     */
    function bucketExchangeRate(uint256 index_) external view returns (uint256 exchangeRate_);

    /**
     *  @notice Called by `LP` owners to allow addresses that can transfer LP.
     *  @dev    Intended for use by the `PositionManager` contract.
     *  @param  transferors_ Addresses that are allowed to transfer `LP` to new owner.
     */
    function approveLPTransferors(address[] calldata transferors_) external;

    /**
     *  @notice Called by `LP` owners to approve transfer of an amount of `LP` to a new owner.
     *  @dev    Intended for use by the `PositionManager` contract.
     *  @param  spender_ The new owner of the `LP`.
     *  @param  indexes_ Bucket indexes from where `LP` are transferred.
     *  @param  amounts_ The amounts of `LP` approved to transfer (`WAD` precision).
     */
    function increaseLPAllowance(address spender_, uint256[] calldata indexes_, uint256[] calldata amounts_) external;

    /**
     *  @notice Called by `LP` owners to transfers their `LP` to a different address. `approveLpOwnership` needs to be run first.
     *  @dev    Used by `PositionManager.memorializePositions()`.
     *  @param  owner_    The original owner address of the position.
     *  @param  newOwner_ The new owner address of the position.
     *  @param  indexes_  Array of price buckets index at which `LP` were moved.
     */
    function transferLP(address owner_, address newOwner_, uint256[] calldata indexes_) external;
}
