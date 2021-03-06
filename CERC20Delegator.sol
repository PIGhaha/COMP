pragma solidity ^0.5.16;

import "./CTokenInterfaces.sol";

/**

 * @title Compound's CErc20Delegator Contract

 * @notice CTokens which wrap an EIP-20 underlying and delegate to an implementation

 * @author Compound
   */
   contract CErc20Delegator is CTokenInterface, CErc20Interface, CDelegatorInterface {
   /**

    * @notice Construct a new money market

    * @param underlying_ The address of the underlying asset

    * @param comptroller_ The address of the Comptroller

    * @param interestRateModel_ The address of the interest rate model

    * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18

    * @param name_ ERC-20 name of this token

    * @param symbol_ ERC-20 symbol of this token

    * @param decimals_ ERC-20 decimal precision of this token

    * @param admin_ Address of the administrator of this token

    * @param implementation_ The address of the implementation the contract delegates to

    * @param becomeImplementationData The encoded args for becomeImplementation
      */
      constructor(address underlying_,        //基础资产
              ComptrollerInterface comptroller_,  //comptroller
              InterestRateModel interestRateModel_,   //利率模型，允许不同的币种有不同的利率模型
              uint initialExchangeRateMantissa_,      //初始兑换率
              string memory name_,
              string memory symbol_,
              uint8 decimals_,
              address payable admin_,     //允许不同的币种有不同的admin
              address implementation_,    //delegate，允许有不同的delegate
              bytes memory becomeImplementationData) public {     //TODO　这个参数的含义？
      // Creator of the contract is admin during initialization
      admin = msg.sender;

      // First delegate gets to initialize the delegator (i.e. storage contract)
      // 就是让delegate去call这个abi进行初始化
      delegateTo(implementation_, abi.encodeWithSignature("initialize(address,address,address,uint256,string,string,uint8)",
                                                          underlying_,
                                                          comptroller_,
                                                          interestRateModel_,
                                                          initialExchangeRateMantissa_,
                                                          name_,
                                                          symbol_,
                                                          decimals_));

      // New implementations always get set via the settor (post-initialize)
      _setImplementation(implementation_, false, becomeImplementationData);

      // Set the proper admin now that initialization is done
      admin = admin_;
      }

   /**

    * @notice Called by the admin to update the implementation of the delegator

    * @param implementation_ The address of the new implementation for delegation

    * @param allowResign Flag to indicate whether to call _resignImplementation on the old implementation

    * @param becomeImplementationData The encoded bytes data to be passed to _becomeImplementation
      */
      //TODO delegate是可以重新设置的，但是为什么需要重新设置delegate?
      function _setImplementation(address implementation_, bool allowResign, bytes memory becomeImplementationData) public {
      require(msg.sender == admin, "CErc20Delegator::_setImplementation: Caller must be admin");

      if (allowResign) {
      //TODO 让delegate去call这个abi,这个_resignImplementation()的作用？
          delegateToImplementation(abi.encodeWithSignature("_resignImplementation()"));
      }

      address oldImplementation = implementation;
      implementation = implementation_;
      //TODO 这个_becomeImplementation的作用？
      delegateToImplementation(abi.encodeWithSignature("_becomeImplementation(bytes)", becomeImplementationData));

      emit NewImplementation(oldImplementation, implementation);
      }

   /**

    * @notice Sender supplies assets into the market and receives cTokens in exchange
    * @dev Accrues interest whether or not the operation succeeds, unless reverted
    * @param mintAmount The amount of the underlying asset to supply
    * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
      function mint(uint mintAmount) external returns (uint) {
      mintAmount; // Shh
      delegateAndReturn();
      }

   /**

    * @notice Sender redeems cTokens in exchange for the underlying asset
    * @dev Accrues interest whether or not the operation succeeds, unless reverted
    * @param redeemTokens The number of cTokens to redeem into underlying
    * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
      function redeem(uint redeemTokens) external returns (uint) {
      redeemTokens; // Shh
      delegateAndReturn();
      }

   /**

    * @notice Sender redeems cTokens in exchange for a specified amount of underlying asset
    * @dev Accrues interest whether or not the operation succeeds, unless reverted
    * @param redeemAmount The amount of underlying to redeem
    * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
      function redeemUnderlying(uint redeemAmount) external returns (uint) {
      redeemAmount; // Shh
      delegateAndReturn();
      }

   /**

     * @notice Sender borrows assets from the protocol to their own address
     * @param borrowAmount The amount of the underlying asset to borrow
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
       */
       function borrow(uint borrowAmount) external returns (uint) {
       borrowAmount; // Shh
       delegateAndReturn();
       }

   /**

    * @notice Sender repays their own borrow
    * @param repayAmount The amount to repay
    * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
      function repayBorrow(uint repayAmount) external returns (uint) {
      repayAmount; // Shh
      delegateAndReturn();
      }

   /**

    * @notice Sender repays a borrow belonging to borrower
    * @param borrower the account with the debt being payed off
    * @param repayAmount The amount to repay
    * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
      function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint) {
      borrower; repayAmount; // Shh
      delegateAndReturn();
      }

   /**

    * @notice The sender liquidates the borrowers collateral.
    * The collateral seized is transferred to the liquidator.
    * @param borrower The borrower of this cToken to be liquidated 借款人地址
    * @param cTokenCollateral The market in which to seize collateral from the borrower 抵押资产池地址
    * @param repayAmount The amount of the underlying borrowed asset to repay 借出的基础资产金额
    * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
      function liquidateBorrow(address borrower, uint repayAmount, CTokenInterface cTokenCollateral) external returns (uint) {
      borrower; repayAmount; cTokenCollateral; // Shh
      delegateAndReturn();
      }

   /**

    * @notice Transfer `amount` tokens from `msg.sender` to `dst`
    * @param dst The address of the destination account
    * @param amount The number of tokens to transfer
    * @return Whether or not the transfer succeeded
      */
      function transfer(address dst, uint amount) external returns (bool) {
      dst; amount; // Shh
      delegateAndReturn();
      }

   /**

    * @notice Transfer `amount` tokens from `src` to `dst`
    * @param src The address of the source account
    * @param dst The address of the destination account
    * @param amount The number of tokens to transfer
    * @return Whether or not the transfer succeeded
      */
      function transferFrom(address src, address dst, uint256 amount) external returns (bool) {
      src; dst; amount; // Shh
      delegateAndReturn();
      }

   /**

    * @notice Approve `spender` to transfer up to `amount` from `src`
    * @dev This will overwrite the approval amount for `spender`
    * and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
    * @param spender The address of the account which may transfer tokens
    * @param amount The number of tokens that are approved (-1 means infinite)
    * @return Whether or not the approval succeeded
      */
      function approve(address spender, uint256 amount) external returns (bool) {
      spender; amount; // Shh
      delegateAndReturn();
      }

   /**

    * @notice Get the current allowance from `owner` for `spender`
    * @param owner The address of the account which owns the tokens to be spent
    * @param spender The address of the account which may transfer tokens
    * @return The number of tokens allowed to be spent (-1 means infinite)
      */
      function allowance(address owner, address spender) external view returns (uint) {
      owner; spender; // Shh
      delegateToViewAndReturn();
      }

   /**

    * @notice Get the token balance of the `owner`
    * @param owner The address of the account to query
    * @return The number of tokens owned by `owner`
      */
      function balanceOf(address owner) external view returns (uint) {
      owner; // Shh
      delegateToViewAndReturn();
      }

   /**

    * @notice Get the underlying balance of the `owner`
    * @dev This also accrues interest in a transaction
    * @param owner The address of the account to query
    * @return The amount of underlying owned by `owner`
      */
      function balanceOfUnderlying(address owner) external returns (uint) {
      owner; // Shh
      delegateAndReturn();
      }

   /**

    * @notice Get a snapshot of the account's balances, and the cached exchange rate
    * @dev This is used by comptroller to more efficiently perform liquidity checks.
    * @param account Address of the account to snapshot
    * @return (possible error, token balance, borrow balance, exchange rate mantissa)
      */
      function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint) {
      account; // Shh
      delegateToViewAndReturn();
      }

   /**

    * @notice Returns the current per-block borrow interest rate for this cToken
    * @return The borrow interest rate per block, scaled by 1e18
      */
      function borrowRatePerBlock() external view returns (uint) {
      delegateToViewAndReturn();
      }

   /**

    * @notice Returns the current per-block supply interest rate for this cToken
    * @return The supply interest rate per block, scaled by 1e18
      */
      function supplyRatePerBlock() external view returns (uint) {
      delegateToViewAndReturn();
      }

   /**

    * @notice Returns the current total borrows plus accrued interest
    * @return The total borrows with interest
      */
      function totalBorrowsCurrent() external returns (uint) {
      delegateAndReturn();
      }

   /**

    * @notice Accrue interest to updated borrowIndex and then calculate account's borrow balance using the updated borrowIndex
    * @param account The address whose balance should be calculated after updating borrowIndex
    * @return The calculated balance
      */
      function borrowBalanceCurrent(address account) external returns (uint) {
      account; // Shh
      delegateAndReturn();
      }

   /**

    * @notice Return the borrow balance of account based on stored data
    * @param account The address whose balance should be calculated
    * @return The calculated balance
      */
      function borrowBalanceStored(address account) public view returns (uint) {
      account; // Shh
      delegateToViewAndReturn();
      }

   /**

     * @notice Accrue interest then return the up-to-date exchange rate
     * @return Calculated exchange rate scaled by 1e18
       */
        function exchangeRateCurrent() public returns (uint) {
       delegateAndReturn();
        }

    /**

     * @notice Calculates the exchange rate from the underlying to the CToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return Calculated exchange rate scaled by 1e18
       */
        function exchangeRateStored() public view returns (uint) {
       delegateToViewAndReturn();
        }

    /**

     * @notice Get cash balance of this cToken in the underlying asset
     * @return The quantity of underlying asset owned by this contract
       */
        function getCash() external view returns (uint) {
       delegateToViewAndReturn();
        }

    /**

      * @notice Applies accrued interest to total borrows and reserves.
      * @dev This calculates interest accrued from the last checkpointed block
      * up to the current block and writes new checkpoint to storage.
           */
         function accrueInterest() public returns (uint) {
        delegateAndReturn();
         }

    /**

     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @dev Will fail unless called by another cToken during the process of liquidation.
     * Its absolutely critical to use msg.sender as the borrowed cToken and not a parameter.
     * @param liquidator The account receiving seized collateral
     * @param borrower The account having collateral seized
     * @param seizeTokens The number of cTokens to seize
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
       */
        function seize(address liquidator, address borrower, uint seizeTokens) external returns (uint) {
       liquidator; borrower; seizeTokens; // Shh
       delegateAndReturn();
        }

    /*** Admin Functions ***/

    /**

      * @notice Begins transfer of admin rights. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
      * @dev Admin function to begin change of admin. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
      * @param newPendingAdmin New pending admin.
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
        */
         function _setPendingAdmin(address payable newPendingAdmin) external returns (uint) {
        newPendingAdmin; // Shh
        delegateAndReturn();
         }

    /**

      * @notice Sets a new comptroller for the market
      * @dev Admin function to set a new comptroller
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
        */
         function _setComptroller(ComptrollerInterface newComptroller) public returns (uint) {
        newComptroller; // Shh
        delegateAndReturn();
         }

    /**

      * @notice accrues interest and sets a new reserve factor for the protocol using _setReserveFactorFresh
      * @dev Admin function to accrue interest and set a new reserve factor
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
        */
         function _setReserveFactor(uint newReserveFactorMantissa) external returns (uint) {
        newReserveFactorMantissa; // Shh
        delegateAndReturn();
         }

    /**

      * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
      * @dev Admin function for pending admin to accept role and update admin
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
        */
         function _acceptAdmin() external returns (uint) {
        delegateAndReturn();
         }

    /**

     * @notice Accrues interest and adds reserves by transferring from admin
     * @param addAmount Amount of reserves to add
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
       */
        function _addReserves(uint addAmount) external returns (uint) {
       addAmount; // Shh
       delegateAndReturn();
        }

    /**

     * @notice Accrues interest and reduces reserves by transferring to admin
     * @param reduceAmount Amount of reduction to reserves
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
       */
        function _reduceReserves(uint reduceAmount) external returns (uint) {
       reduceAmount; // Shh
       delegateAndReturn();
        }

    /**

     * @notice Accrues interest and updates the interest rate model using _setInterestRateModelFresh
     * @dev Admin function to accrue interest and update the interest rate model
     * @param newInterestRateModel the new interest rate model to use
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
       */
        function _setInterestRateModel(InterestRateModel newInterestRateModel) public returns (uint) {
       newInterestRateModel; // Shh
       delegateAndReturn();
        }

    /**

     * @notice Internal method to delegate execution to another contract
     * @dev It returns to the external caller whatever the implementation returns or forwards reverts
     * @param callee The contract to delegatecall
     * @param data The raw data to delegatecall
     * @return The returned bytes from the delegatecall
       */

    // TODO callee:被召唤者，就是delegate
    // 就是让delegate去call这个data
    function delegateTo(address callee, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returnData) = callee.delegatecall(data);    //TODO 让callee去call这个data，不改变上下文
        assembly {
            if eq(success, 0) {
                revert(add(returnData, 0x20), returndatasize)
            }
        }
        return returnData;
    }

    /**

     * @notice Delegates execution to the implementation contract
     * @dev It returns to the external caller whatever the implementation returns or forwards reverts
     * @param data The raw data to delegatecall
     * @return The returned bytes from the delegatecall
       */
        //TODO 提供一个外部方法，让delegate去call这个data
        function delegateToImplementation(bytes memory data) public returns (bytes memory) {
       return delegateTo(implementation, data);
        }

    /**

     * @notice Delegates execution to an implementation contract

     * @dev It returns to the external caller whatever the implementation returns or forwards reverts

     * There are an additional 2 prefix uints from the wrapper returndata, which we ignore since we make an extra hop.

     * @param data The raw data to delegatecall

     * @return The returned bytes from the delegatecall
       */
        //TODO 与上一个方法的区别是：这个方法只提供只读的调用
        function delegateToViewImplementation(bytes memory data) public view returns (bytes memory) {
       (bool success, bytes memory returnData) = address(this).staticcall(abi.encodeWithSignature("delegateToImplementation(bytes)", data));
       // TODO staticcall 不修改状态变量的call操作，如果有修改则会回滚，
       assembly {
           if eq(success, 0) {
               revert(add(returnData, 0x20), returndatasize)   //TODO 需要学习内联汇编
           }
       }
       return abi.decode(returnData, (bytes));
        }
        //TODO 供view的方法来调用
        function delegateToViewAndReturn() private view returns (bytes memory) {
       (bool success, ) = address(this).staticcall(abi.encodeWithSignature("delegateToImplementation(bytes)", msg.data));

       assembly {
           let free_mem_ptr := mload(0x40)
           returndatacopy(free_mem_ptr, 0, returndatasize)

           switch success
           case 0 { revert(free_mem_ptr, returndatasize) }
           default { return(add(free_mem_ptr, 0x40), returndatasize) }

       }
        }
        //TODO 供需要修改状态变量的方法来调用
        function delegateAndReturn() private returns (bytes memory) {
       (bool success, ) = implementation.delegatecall(msg.data);

       assembly {
           let free_mem_ptr := mload(0x40)
           returndatacopy(free_mem_ptr, 0, returndatasize)

           switch success
           case 0 { revert(free_mem_ptr, returndatasize) }
           default { return(free_mem_ptr, returndatasize) }

       }
        }

    /**

     * @notice Delegates execution to an implementation contract

     * @dev It returns to the external caller whatever the implementation returns or forwards reverts
       */
        // TODO 匿名函数？
        function () external payable {
       require(msg.value == 0,"CErc20Delegator:fallback: cannot send value to fallback");

       // delegate all other functions to current implementation
       delegateAndReturn();
        }
       }
