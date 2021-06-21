pragma solidity ^0.5.16;

import "./CToken.sol";
import "./ErrorReporter.sol";
import "./Exponential.sol";
import "./PriceOracle.sol";
import "./ComptrollerInterface.sol";
import "./ComptrollerStorage.sol";
import "./Unitroller.sol";
import "./Comp.sol";

/**

 * @title Compound's Comptroller Contract

 * @author Compound
   */
   contract Comptroller is ComptrollerV3Storage, ComptrollerInterface, ComptrollerErrorReporter, Exponential {
   /// @notice Emitted when an admin supports a market
   event MarketListed(CToken cToken);      //每新增一个市场，触发一次事件

   /// @notice Emitted when an account enters a market
   event MarketEntered(CToken cToken, address account);    //每当一个账户进入一个市场，触发一次事件

   /// @notice Emitted when an account exits a market
   event MarketExited(CToken cToken, address account);     //每当一个账户退出一个市场，触发一次事件

   /// @notice Emitted when close factor is changed by admin
   event NewCloseFactor(uint oldCloseFactorMantissa, uint newCloseFactorMantissa);
   //TODO 需要被清算的部分占未偿还贷款的百分比，每次清算后更新

   /// @notice Emitted when a collateral factor is changed by admin  //更新抵押因子触发事件
   event NewCollateralFactor(CToken cToken, uint oldCollateralFactorMantissa, uint newCollateralFactorMantissa);

   /// @notice Emitted when liquidation incentive is changed by admin   //更新清算奖励触发事件
   event NewLiquidationIncentive(uint oldLiquidationIncentiveMantissa, uint newLiquidationIncentiveMantissa);

   /// @notice Emitted when maxAssets is changed by admin      //更新最大资产数量触发事件
   event NewMaxAssets(uint oldMaxAssets, uint newMaxAssets);

   /// @notice Emitted when price oracle is changed    //更新价格预言机触发事件
   event NewPriceOracle(PriceOracle oldPriceOracle, PriceOracle newPriceOracle);

   /// @notice Emitted when pause guardian is changed  //TODO 是有权进行pause操作的人吗？
   event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

   /// @notice Emitted when an action is paused globally   //全局pause TODO 那些action可以pause？
   event ActionPaused(string action, bool pauseState);

   /// @notice Emitted when an action is paused on a market    //单市场pause
   event ActionPaused(CToken cToken, string action, bool pauseState);

   /// @notice Emitted when market comped status is changed    //某个市场是否启动挖矿的状态改变时触发事件
   event MarketComped(CToken cToken, bool isComped);

   /// @notice Emitted when COMP rate is changed       //挖矿速率更新时触发事件
   event NewCompRate(uint oldCompRate, uint newCompRate);

   /// @notice Emitted when a new COMP speed is calculated for a market    //挖矿速率更新时触发事件
   event CompSpeedUpdated(CToken indexed cToken, uint newSpeed);

   /// @notice Emitted when COMP is distributed to a supplier
   event DistributedSupplierComp(CToken indexed cToken, address indexed supplier, uint compDelta, uint compSupplyIndex);
   //当COMP币分发给某个存款人时触发事件
   //TODO compDelta和compSupplyIndex分别代表什么？

   /// @notice Emitted when COMP is distributed to a borrower        //当COMP币分发给某个借款人时触发事件
   event DistributedBorrowerComp(CToken indexed cToken, address indexed borrower, uint compDelta, uint compBorrowIndex);

   /// @notice The threshold above which the flywheel transfers COMP, in wei
   uint public constant compClaimThreshold = 0.001e18;
   //TODO Claim COMP币的门槛值，小于0.001的COMP币将不会被claim出来？

   /// @notice The initial COMP index for a market  TODO 这个index的作用？
   uint224 public constant compInitialIndex = 1e36;
   //TODO 这是一个borrow index 的初始值


    // closeFactorMantissa must be strictly greater than this value
    uint internal constant closeFactorMinMantissa = 0.05e18; // 0.05
    //TODO 需要被清算的部分占全部借款额的比例必须大于0.05
    
    // closeFactorMantissa must not exceed this value
    uint internal constant closeFactorMaxMantissa = 0.9e18; // 0.9
    //TODO 需要被清算的部分占全部借款额的比例必须小于0.9
    
    // No collateralFactorMantissa may exceed this value
    uint internal constant collateralFactorMaxMantissa = 0.9e18; // 0.9
    //抵押因子最大不超过0.9
    
    // liquidationIncentiveMantissa must be no less than this value
    uint internal constant liquidationIncentiveMinMantissa = 1.0e18; // 1.0
    //清算奖励因子不低于1.0
    
    // liquidationIncentiveMantissa must be no greater than this value
    uint internal constant liquidationIncentiveMaxMantissa = 1.5e18; // 1.5
    //清算奖励因子不高于1.5
    
    constructor() public {
        admin = msg.sender;
    }
    
    /*** Assets You Are In ***/
    
    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A dynamic list with the assets the account has entered
     */
    function getAssetsIn(address account) external view returns (CToken[] memory) {
        CToken[] memory assetsIn = accountAssets[account];
        //accountAssets维护一个account到CToken[]的mapping，代表该账户进入的代币市场
        return assetsIn;
    }
    //获得一个账户已进入的所有市场
    
    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param cToken The cToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkMembership(address account, CToken cToken) external view returns (bool) {
        return markets[address(cToken)].accountMembership[account];
    }
    //检查某个账户是否在某个市场，调用的是markets映射（address(cToken)=>market）,market结构体中保存了(address(user)=>bool)的映射
    
    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param cTokens The list of addresses of the cToken markets to be enabled
     * @return Success indicator for whether each corresponding market was entered
     */
    function enterMarkets(address[] memory cTokens) public returns (uint[] memory) {
        uint len = cTokens.length;
    
        uint[] memory results = new uint[](len);
        for (uint i = 0; i < len; i++) {
            CToken cToken = CToken(cTokens[i]);
    
            results[i] = uint(addToMarketInternal(cToken, msg.sender));     //TODO 注意将枚举类型强制转换为其下标的用法
        }
    
        return results;
    }
    //加入流动性市场
    //TODO 返回值是一个将Error枚举类型强制转化为其下标的数组，为什么在remix界面看不到返回值？
    //TODO 在哪里可以看到返回值？
    
    /**
     * @notice Add the market to the borrower's "assets in" for liquidity calculations
     * @param cToken The market to enter
     * @param borrower The address of the account to modify
     * @return Success indicator for whether the market was entered
     */
    function addToMarketInternal(CToken cToken, address borrower) internal returns (Error) {
        Market storage marketToJoin = markets[address(cToken)];     //TODO 为什么要用storage类型？
    
        if (!marketToJoin.isListed) {       //TODO isListed在哪里进行设置？
            // market is not listed, cannot join
            return Error.MARKET_NOT_LISTED;
        }
    
        if (marketToJoin.accountMembership[borrower] == true) {     //如已加入则返回No_ERROR
            // already joined
            return Error.NO_ERROR;
        }
    
        if (accountAssets[borrower].length >= maxAssets)  {     //限制每个人加入的资金池的数量，TODO　为什么要限制？
            // no space, cannot join
            return Error.TOO_MANY_ASSETS;
        }
        //TODO 因为addToMarket操作是逐个进行的，所以用户进入资金池的数量一定小于maxAssets
    
        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        marketToJoin.accountMembership[borrower] = true;
        accountAssets[borrower].push(cToken);   //在CToken[] 数组中加入这个新的cToken
    
        emit MarketEntered(cToken, borrower);
    
        return Error.NO_ERROR;
    }
    
    /**
     * @notice Removes asset from sender's account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param cTokenAddress The address of the asset to be removed
     * @return Whether or not the account successfully exited the market
     */
    function exitMarket(address cTokenAddress) external returns (uint) {
        CToken cToken = CToken(cTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the cToken */
        (uint oErr, uint tokensHeld, uint amountOwed, ) = cToken.getAccountSnapshot(msg.sender);
        //获得了错误值，存款值cToken值，欠款值，未接收兑换率


        require(oErr == 0, "exitMarket: getAccountSnapshot failed"); // semi-opaque error code
    
        /* Fail if the sender has a borrow balance 如果在该市场有欠款则不允许退出市场*/
        if (amountOwed != 0) {
            return fail(Error.NONZERO_BORROW_BALANCE, FailureInfo.EXIT_MARKET_BALANCE_OWED);  //触发error事件，并返回error下标
        }
        //TODO 注意：在没有entermarket的状态下进行借款，会先自动执行entermarket操作，还款后还是entermarket的状态
    
        //TODO  已经有借款的市场不允许exitMarket,没有借款的市场在exitMarket之前会检查是否符合提现的条件，因为exitMarket之后就能自由提现
        /* Fail if the sender is not permitted to redeem all of their tokens */
        uint allowed = redeemAllowedInternal(cTokenAddress, msg.sender, tokensHeld);
        //TODO exitMarket包含了检查是否可以赎回cToken的动作，因此需要检查赎回cToken之后是否会造成流动性不足
        //返回的allowed是错误编号
    
        if (allowed != 0) {
            return failOpaque(Error.REJECTION, FailureInfo.EXIT_MARKET_REJECTION, allowed);
        }
    
        Market storage marketToExit = markets[address(cToken)];
    
        /* Return true if the sender is not already ‘in’ the market */
        if (!marketToExit.accountMembership[msg.sender]) {
            return uint(Error.NO_ERROR);
        }
        //如果账户没有加入过市场返回错误编号为0
    
        /* Set cToken account membership to false */
        delete marketToExit.accountMembership[msg.sender];
        //否则删除映射中的msg.sender，效果相当于设为false
    
        /* Delete cToken from the account’s list of assets */
        // load into memory for faster iteration
        CToken[] memory userAssetList = accountAssets[msg.sender];
        uint len = userAssetList.length;
        uint assetIndex = len;
        for (uint i = 0; i < len; i++) {
            if (userAssetList[i] == cToken) {
                assetIndex = i;
                break;
            }
        }
    
        // We *must* have found the asset in the list or our redundant data structure is broken
        assert(assetIndex < len);
    
        // copy last item in list to location of item to be removed, reduce length by 1
        CToken[] storage storedList = accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.length--;
        //TODO 注意这个版本的.length还是可写操作，通过执行length--达到删除数组最后一个元素的效果
    
        emit MarketExited(cToken, msg.sender);
    
        return uint(Error.NO_ERROR);
    }
    
    /*** Policy Hooks ***/
    
    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param cToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     * @return 0 if the mint is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function mintAllowed(address cToken, address minter, uint mintAmount) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!mintGuardianPaused[cToken], "mint is paused");  //检查mint功能是否已被管理员暂停
    
        // Shh - currently unused  TODO Shh:嘘 这两个变量目前未使用，放在这里也不影响编译
        minter;
        mintAmount;
    
        if (!markets[cToken].isListed) {        //需要先supportmarket
            return uint(Error.MARKET_NOT_LISTED);
        }


        // Keep the flywheel moving
        updateCompSupplyIndex(cToken);      //TODO 为什么要在这里更新收益指数和分发Can币？
        distributeSupplierComp(cToken, minter, false);
    
        return uint(Error.NO_ERROR);
    }
    
    /**
     * @notice Validates mint and reverts on rejection. May emit logs.
     * @param cToken Asset being minted
     * @param minter The address minting the tokens
     * @param actualMintAmount The amount of the underlying asset being minted
     * @param mintTokens The number of tokens being minted
     */
    function mintVerify(address cToken, address minter, uint actualMintAmount, uint mintTokens) external {
        // Shh - currently unused
        cToken;
        minter;
        actualMintAmount;
        mintTokens;
    
        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }
    //TODO 这个方法暂时没有用到，为什么要设计这个外部方法？

/**

 * @notice Checks if the account should be allowed to redeem tokens in the given market

 * @param cToken The market to verify the redeem against

 * @param redeemer The account which would redeem the tokens

 * @param redeemTokens The number of cTokens to exchange for the underlying asset in the market

 * @return 0 if the redeem is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
   */
   function redeemAllowed(address cToken, address redeemer, uint redeemTokens) external returns (uint) {
       uint allowed = redeemAllowedInternal(cToken, redeemer, redeemTokens);
       if (allowed != uint(Error.NO_ERROR)) {
           return allowed;
       }

       // Keep the flywheel moving
       updateCompSupplyIndex(cToken);            //redeem时更新存钱的收益指数并获得在这个市场存钱部分的Can币
       distributeSupplierComp(cToken, redeemer, false);
       
       return uint(Error.NO_ERROR);

   }

   function redeemAllowedInternal(address cToken, address redeemer, uint redeemTokens) internal view returns (uint) {
       if (!markets[cToken].isListed) {
           return uint(Error.MARKET_NOT_LISTED);
       }
       //判断comptroller是否support过这个cToken

       /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
       if (!markets[cToken].accountMembership[redeemer]) {     //markets是从cToken到这个cToken的基本信息结构体Market的映射
           return uint(Error.NO_ERROR);
       }
       // 未抵押的资产可以随时提现
       
       /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
       (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(redeemer, CToken(cToken), redeemTokens, 0);
       //检查操作后的预测亏空
       if (err != Error.NO_ERROR) {
           return uint(err);
       }
       if (shortfall > 0) {    //如果将产生亏空，将返回流动性不足的错误
           return uint(Error.INSUFFICIENT_LIQUIDITY);
       }
       
       return uint(Error.NO_ERROR);

   }

   /**

    * @notice Validates redeem and reverts on rejection. May emit logs.

    * @param cToken Asset being redeemed

    * @param redeemer The address redeeming the tokens

    * @param redeemAmount The amount of the underlying asset being redeemed

    * @param redeemTokens The number of tokens being redeemed
      */
      function redeemVerify(address cToken, address redeemer, uint redeemAmount, uint redeemTokens) external {
      // Shh - currently unused
      cToken;
      redeemer;

      // Require tokens is zero or amount is also zero
      if (redeemTokens == 0 && redeemAmount > 0) {
          revert("redeemTokens zero");
      }
      }
      //TODO 这个方法暂时没有用到，为什么要设计这个外部方法？

   /**

    * @notice Checks if the account should be allowed to borrow the underlying asset of the given market

    * @param cToken The market to verify the borrow against

    * @param borrower The account which would borrow the asset

    * @param borrowAmount The amount of underlying the account would borrow

    * @return 0 if the borrow is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
      */
      function borrowAllowed(address cToken, address borrower, uint borrowAmount) external returns (uint) {
      // Pausing is a very serious situation - we revert to sound the alarms
      require(!borrowGuardianPaused[cToken], "borrow is paused");     //判断守护者是否暂停了借款，TODO 注意不是管理员

      if (!markets[cToken].isListed) {        //判断是否已经support过market
          return uint(Error.MARKET_NOT_LISTED);
      }

      if (!markets[cToken].accountMembership[borrower]) {
          // only cTokens may call borrowAllowed if borrower not in market
          require(msg.sender == cToken, "sender must be cToken");
          //TODO 如果borrower不在这个市场，那么只有这个cToken能调用这个方法，为什么这样设计?
          //TODO 因为下面要做一个entermarket的操作，因此要求必须是cToken发起的，防止恶意合约修改用户状态
          //TODO 需要弄清楚cToken在什么时候会调用这个方法

          // attempt to add borrower to the market
          Error err = addToMarketInternal(CToken(msg.sender), borrower);
          if (err != Error.NO_ERROR) {
              return uint(err);
          }
          //TODO 注意borrow的时候实际上已经做了entermarket的操作
          
          // it should be impossible to break the important invariant
          assert(markets[cToken].accountMembership[borrower]);    //判断是否加入成功

      }

      if (oracle.getUnderlyingPrice(CToken(cToken)) == 0) {
          return uint(Error.PRICE_ERROR);
      }
      //TODO 注意如果预言机获取不到价格，借款会失败

      (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(borrower, CToken(cToken), 0, borrowAmount);
      if (err != Error.NO_ERROR) {
          return uint(err);
      }
      if (shortfall > 0) {
          return uint(Error.INSUFFICIENT_LIQUIDITY);
      }
      //进行流动性判断

      // Keep the flywheel moving
      Exp memory borrowIndex = Exp({mantissa: CToken(cToken).borrowIndex()});
      updateCompBorrowIndex(cToken, borrowIndex);    //TODO 为什么时在做borrowAllowed操作时更新借款利息指数和分发Can币？
      distributeBorrowerComp(cToken, borrower, borrowIndex, false);

      return uint(Error.NO_ERROR);
      }

   /**

    * @notice Validates borrow and reverts on rejection. May emit logs.

    * @param cToken Asset whose underlying is being borrowed

    * @param borrower The address borrowing the underlying

    * @param borrowAmount The amount of the underlying asset requested to borrow
      */
      function borrowVerify(address cToken, address borrower, uint borrowAmount) external {
      // Shh - currently unused
      cToken;
      borrower;
      borrowAmount;

      // Shh - we don't ever want this hook to be marked pure
      if (false) {
          maxAssets = maxAssets;
      }
      }
      //暂时未用到这个方法

   /**

    * @notice Checks if the account should be allowed to repay a borrow in the given market

    * @param cToken The market to verify the repay against

    * @param payer The account which would repay the asset

    * @param borrower The account which would borrowed the asset

    * @param repayAmount The amount of the underlying asset the account would repay

    * @return 0 if the repay is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
      */
      function repayBorrowAllowed(
      address cToken,
      address payer,
      address borrower,
      uint repayAmount) external returns (uint) {
      // Shh - currently unused
      payer;
      borrower;
      repayAmount;

      if (!markets[cToken].isListed) {
          return uint(Error.MARKET_NOT_LISTED);
      }

      // Keep the flywheel moving
      Exp memory borrowIndex = Exp({mantissa: CToken(cToken).borrowIndex()});
      updateCompBorrowIndex(cToken, borrowIndex);  //TODO 为什么时在做borrowAllowed操作时更新借款利息指数和分发Can币？
      distributeBorrowerComp(cToken, borrower, borrowIndex, false);

      return uint(Error.NO_ERROR);
      }
      //TODO 这个方法好像支持一个账户给另一个账户还款，但是这个方法暂时未用到

   /**

    * @notice Validates repayBorrow and reverts on rejection. May emit logs.

    * @param cToken Asset being repaid

    * @param payer The address repaying the borrow

    * @param borrower The address of the borrower

    * @param actualRepayAmount The amount of underlying being repaid
      */
      function repayBorrowVerify(
      address cToken,
      address payer,
      address borrower,
      uint actualRepayAmount,
      uint borrowerIndex) external {
      // Shh - currently unused
      cToken;
      payer;
      borrower;
      actualRepayAmount;
      borrowerIndex;

      // Shh - we don't ever want this hook to be marked pure
      if (false) {
          maxAssets = maxAssets;
      }
      }
      //暂未用到的方法

   /**

    * @notice Checks if the liquidation should be allowed to occur

    * @param cTokenBorrowed Asset which was borrowed by the borrower

    * @param cTokenCollateral Asset which was used as collateral and will be seized

    * @param liquidator The address repaying the borrow and seizing the collateral

    * @param borrower The address of the borrower

    * @param repayAmount The amount of underlying being repaid
      */
      function liquidateBorrowAllowed(
      address cTokenBorrowed,
      address cTokenCollateral,
      address liquidator,
      address borrower,
      uint repayAmount) external returns (uint) {
      // Shh - currently unused
      liquidator;

      if (!markets[cTokenBorrowed].isListed || !markets[cTokenCollateral].isListed) {
          return uint(Error.MARKET_NOT_LISTED);
      }

      /* The borrower must have shortfall in order to be liquidatable */
      (Error err, , uint shortfall) = getAccountLiquidityInternal(borrower);
      if (err != Error.NO_ERROR) {
          return uint(err);
      }
      if (shortfall == 0) {
          return uint(Error.INSUFFICIENT_SHORTFALL);
          //TODO 借款人要有亏空才能被清算
          //TODO 注意这里亏空是根据流动性来计算得到的，即使抵押物价值比欠款价值高，只要亏空大于0，就可以被清算
      }

      /* The liquidator may not repay more than what is allowed by the closeFactor */
      uint borrowBalance = CToken(cTokenBorrowed).borrowBalanceStored(borrower);
      (MathError mathErr, uint maxClose) = mulScalarTruncate(Exp({mantissa: closeFactorMantissa}), borrowBalance);
      // TODO 根据关闭因子计算最大的可被清算金额

      if (mathErr != MathError.NO_ERROR) {
          return uint(Error.MATH_ERROR);
      }
      if (repayAmount > maxClose) {       //每次只能清算不超过maxClose金额的数值
          return uint(Error.TOO_MUCH_REPAY);
      }

      return uint(Error.NO_ERROR);
      }
      // TODO 清算还款需要满足的条件：
      //1.需要清算的借出货币和抵押货币都应在comptroller中support过market
      //2.借款人亏空需要大于0
      //3.清算金额需要小于最大可被清算额（由清算因子决定）

   /**

    * @notice Validates liquidateBorrow and reverts on rejection. May emit logs.

    * @param cTokenBorrowed Asset which was borrowed by the borrower

    * @param cTokenCollateral Asset which was used as collateral and will be seized

    * @param liquidator The address repaying the borrow and seizing the collateral

    * @param borrower The address of the borrower

    * @param actualRepayAmount The amount of underlying being repaid
      */
      function liquidateBorrowVerify(
      address cTokenBorrowed,
      address cTokenCollateral,
      address liquidator,
      address borrower,
      uint actualRepayAmount,
      uint seizeTokens) external {
      // Shh - currently unused
      cTokenBorrowed;
      cTokenCollateral;
      liquidator;
      borrower;
      actualRepayAmount;
      seizeTokens;

      // Shh - we don't ever want this hook to be marked pure
      if (false) {
          maxAssets = maxAssets;
      }
      }
      //这个方法暂时不用

   /**

    * @notice Checks if the seizing of assets should be allowed to occur
    * @param cTokenCollateral Asset which was used as collateral and will be seized
    * @param cTokenBorrowed Asset which was borrowed by the borrower
    * @param liquidator The address repaying the borrow and seizing the collateral
    * @param borrower The address of the borrower
    * @param seizeTokens The number of collateral tokens to seize
      */

   //TODO 需要弄清楚这个 seizeAllowed 和前面的 liquidateBorrowAllowed 有什么区别？按字面理解是允许获取抵押物
   function seizeAllowed(
       address cTokenCollateral,
       address cTokenBorrowed,
       address liquidator,
       address borrower,
       uint seizeTokens) external returns (uint) {
       // Pausing is a very serious situation - we revert to sound the alarms
       require(!seizeGuardianPaused, "seize is paused");

       // Shh - currently unused
       seizeTokens;
       
       if (!markets[cTokenCollateral].isListed || !markets[cTokenBorrowed].isListed) {
           return uint(Error.MARKET_NOT_LISTED);
       }
       
       if (CToken(cTokenCollateral).comptroller() != CToken(cTokenBorrowed).comptroller()) {
           return uint(Error.COMPTROLLER_MISMATCH);
       }
       // TODO 注意可以为不同的Token设置不同的Comptroller, 如果存在多个comptroller需要注意什么？
       
       // Keep the flywheel moving
       updateCompSupplyIndex(cTokenCollateral);        //更新抵押资产的存款收益指数
       distributeSupplierComp(cTokenCollateral, borrower, false);  //分发抵押资产的存款所得Can币给被清算者
       distributeSupplierComp(cTokenCollateral, liquidator, false);    //分发抵押资产的存款所得Can币给清算者，TODO 这里分多少？
       
       return uint(Error.NO_ERROR);

   }
   //TODO seizeAllowed需要 满足的条件：
   //1.被清算的借款和抵押资产必须在comptroller中被support过
   //2.被清算的借款和抵押资产的comptroller必须相同

   /**

    * @notice Validates seize and reverts on rejection. May emit logs.

    * @param cTokenCollateral Asset which was used as collateral and will be seized

    * @param cTokenBorrowed Asset which was borrowed by the borrower

    * @param liquidator The address repaying the borrow and seizing the collateral

    * @param borrower The address of the borrower

    * @param seizeTokens The number of collateral tokens to seize
      */
      function seizeVerify(
      address cTokenCollateral,
      address cTokenBorrowed,
      address liquidator,
      address borrower,
      uint seizeTokens) external {
      // Shh - currently unused
      cTokenCollateral;
      cTokenBorrowed;
      liquidator;
      borrower;
      seizeTokens;

      // Shh - we don't ever want this hook to be marked pure
      if (false) {
          maxAssets = maxAssets;
      }
      }
      //这个方法暂时不用

   /**

    * @notice Checks if the account should be allowed to transfer tokens in the given market

    * @param cToken The market to verify the transfer against

    * @param src The account which sources the tokens

    * @param dst The account which receives the tokens

    * @param transferTokens The number of cTokens to transfer

    * @return 0 if the transfer is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
      */
      function transferAllowed(address cToken, address src, address dst, uint transferTokens) external returns (uint) {
      // Pausing is a very serious situation - we revert to sound the alarms
      require(!transferGuardianPaused, "transfer is paused");

      // Currently the only consideration is whether or not
      //  the src is allowed to redeem this many tokens
      uint allowed = redeemAllowedInternal(cToken, src, transferTokens);
      //TODO 需要先检查转账是否会造成src的流动性不足的问题
      //TODO 注意这里流动性亏空的检查是按抵押物的流动性计算的（乘过了抵押因子），因此转账可能会导致临近清算线
      if (allowed != uint(Error.NO_ERROR)) {
          return allowed;
      }

      // Keep the flywheel moving
      updateCompSupplyIndex(cToken);           //TODO 此时会更新存款收益指数并给转账人和收款人分发Can币，如何分配？
      distributeSupplierComp(cToken, src, false);
      distributeSupplierComp(cToken, dst, false);

      return uint(Error.NO_ERROR);
      }

   /**

    * @notice Validates transfer and reverts on rejection. May emit logs.

    * @param cToken Asset being transferred

    * @param src The account which sources the tokens

    * @param dst The account which receives the tokens

    * @param transferTokens The number of cTokens to transfer
      */
      function transferVerify(address cToken, address src, address dst, uint transferTokens) external {
      // Shh - currently unused
      cToken;
      src;
      dst;
      transferTokens;

      // Shh - we don't ever want this hook to be marked pure
      if (false) {
          maxAssets = maxAssets;
      }
      }
      //这个方法暂时不用

   /*** Liquidity/Liquidation Calculations ***/

   /**

    * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
    * Note that `cTokenBalance` is the number of cTokens the account owns in the market,
    * whereas `borrowBalance` is the amount of underlying that the account has borrowed.
      */
      //在计算账户流动性时避免堆栈深度限制的本地变量 
      struct AccountLiquidityLocalVars {
      uint sumCollateral;         //TODO 借款人所有抵押物的流动性（按美金计），注意是乘以抵押因子之后得到的数的和
      uint sumBorrowPlusEffects;  //借出的资金总价值（按美金计）
      uint cTokenBalance;         //借款人拥有的cToken的数量
      uint borrowBalance;         //TODO 借出的underlying的数量，推测是包含利息的，待验证
      uint exchangeRateMantissa;  //兑换率
      uint oraclePriceMantissa;   //预言机报价
      Exp collateralFactor;           //TODO Exp是防止堆栈过深的数据结构，如何防止？
      Exp exchangeRate;
      Exp oraclePrice;
      Exp tokensToDenom;      //Token的面值denomination=抵押因子 X 兑换率 X 预言机价格（underlying）
      }

   /**

    * @notice Determine the current account liquidity wrt collateral requirements

    * @return (possible error code (semi-opaque),
         account liquidity in excess of collateral requirements,

    * account shortfall below collateral requirements)
       */
      function getAccountLiquidity(address account) public view returns (uint, uint, uint) {
      (Error err, uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(account, CToken(0), 0, 0);

      return (uint(err), liquidity, shortfall);
      }

   /**

    * @notice Determine the current account liquidity wrt collateral requirements
    * @return (possible error code,
         account liquidity in excess of collateral requirements,
    * account shortfall below collateral requirements)
       */
      function getAccountLiquidityInternal(address account) internal view returns (Error, uint, uint) {
      return getHypotheticalAccountLiquidityInternal(account, CToken(0), 0, 0);
      }

   /**

    * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
    * @param cTokenModify The market to hypothetically redeem/borrow in
    * @param account The account to determine liquidity for
    * @param redeemTokens The number of tokens to hypothetically redeem
    * @param borrowAmount The amount of underlying to hypothetically borrow
    * @return (possible error code (semi-opaque), TODO semi-opaque 半透明
         hypothetical account liquidity in excess of collateral requirements,
    * hypothetical account shortfall below collateral requirements)
       */
      function getHypotheticalAccountLiquidity(
      address account,
      address cTokenModify,      //用户想要执行如redeem/borrow操作的市场
      uint redeemTokens,
      uint borrowAmount) public view returns (uint, uint, uint) {
      (Error err, uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(account, CToken(cTokenModify), redeemTokens, borrowAmount);
      return (uint(err), liquidity, shortfall);
      }

   /**

    * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed

    * @param cTokenModify The market to hypothetically redeem/borrow in

    * @param account The account to determine liquidity for

    * @param redeemTokens The number of tokens to hypothetically redeem

    * @param borrowAmount The amount of underlying to hypothetically borrow

    * @dev Note that we calculate the exchangeRateStored for each collateral cToken using stored data,

    * without calculating accumulated interest.

    * @return (possible error code,
         hypothetical account liquidity in excess of collateral requirements,

    * hypothetical account shortfall below collateral requirements)
       */
      function getHypotheticalAccountLiquidityInternal(
      address account,
      CToken cTokenModify,
      uint redeemTokens,
      uint borrowAmount) internal view returns (Error, uint, uint) {  //TODO 返回错误编号，流动性和预测亏空

      AccountLiquidityLocalVars memory vars; // Holds all our calculation results
      uint oErr;
      MathError mErr;

      // For each asset the account is in 获取该账户entermarket的市场数组
      CToken[] memory assets = accountAssets[account];
      for (uint i = 0; i < assets.length; i++) {
          CToken asset = assets[i];

          // Read the balances and exchange rate from the cToken
          (oErr, vars.cTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = asset.getAccountSnapshot(account);
          if (oErr != 0) { // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
              return (Error.SNAPSHOT_ERROR, 0, 0);
          }
          vars.collateralFactor = Exp({mantissa: markets[address(asset)].collateralFactorMantissa});  //获得该市场的抵押因子
          vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});     //获得该市场的兑换率
          
          // Get the normalized price of the asset
          vars.oraclePriceMantissa = oracle.getUnderlyingPrice(asset);    //从预言机获得价格
          if (vars.oraclePriceMantissa == 0) {
              return (Error.PRICE_ERROR, 0, 0);
          }
          vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});       //TODO 将价格转换为Exp类型,防止堆栈过深
          
          // Pre-compute a conversion factor from tokens -> ether (normalized price value)
          (mErr, vars.tokensToDenom) = mulExp3(vars.collateralFactor, vars.exchangeRate, vars.oraclePrice);
          if (mErr != MathError.NO_ERROR) {
              return (Error.MATH_ERROR, 0, 0);
          }
          //TODO 求得1个Token的标准价格=抵押因子 X 兑换率 X 预言机价格，注意这里乘了抵押因子，表示可借出的价值


            // sumCollateral += tokensToDenom * cTokenBalance 
            (mErr, vars.sumCollateral) = mulScalarTruncateAddUInt(vars.tokensToDenom, vars.cTokenBalance, vars.sumCollateral); 
            //先乘后截断再加        
            if (mErr != MathError.NO_ERROR) {            
              return (Error.MATH_ERROR, 0, 0);        
            }        //TODO  这样算出来的抵押物价值是不带18位小数点的整数部分？Exp类型的数据是已经乘过1e18的        
            //TODO 这里的Exp类型已经是乘以1e18之后的数        
            // sumBorrowPlusEffects += oraclePrice * borrowBalance        
            (mErr, vars.sumBorrowPlusEffects) = mulScalarTruncateAddUInt(vars.oraclePrice, vars.borrowBalance, vars.sumBorrowPlusEffects);        
            if (mErr != MathError.NO_ERROR) {            return (Error.MATH_ERROR, 0, 0);        }        
            //TODO　该账户再所有市场的总的欠款，借款本金＋全局利息        
            // Calculate effects of interacting with cTokenModify        
            if (asset == cTokenModify) {            
            // redeem effect            
            // sumBorrowPlusEffects += tokensToDenom * redeemTokens            
            (mErr, vars.sumBorrowPlusEffects) = mulScalarTruncateAddUInt(vars.tokensToDenom, redeemTokens, vars.sumBorrowPlusEffects);            
            //把要redeem的Token也算到总借出额里            
            if (mErr != MathError.NO_ERROR) {                return (Error.MATH_ERROR, 0, 0);            }
            // borrow effect            
            // sumBorrowPlusEffects += oraclePrice * borrowAmount            
            (mErr, vars.sumBorrowPlusEffects) = mulScalarTruncateAddUInt(vars.oraclePrice, borrowAmount, vars.sumBorrowPlusEffects);            
            //把要借出的Token也算到总借出额里            
            if (mErr != MathError.NO_ERROR) {                return (Error.MATH_ERROR, 0, 0);            }        }    }    
            // These are safe, as the underflow condition is checked first    
            if (vars.sumCollateral > vars.sumBorrowPlusEffects) {        return (Error.NO_ERROR, vars.sumCollateral - vars.sumBorrowPlusEffects, 0);    } 
            else {        return (Error.NO_ERROR, 0, vars.sumBorrowPlusEffects - vars.sumCollateral);    }    
            // 返回错误编号，预测操作后的流动性和亏空}
            /** * @notice Calculate number of tokens of collateral asset to seize given an underlying amount 
            * @dev Used in liquidation (called in cToken.liquidateBorrowFresh) 
            * @param cTokenBorrowed The address of the borrowed cToken * @param cTokenCollateral The address of the collateral cToken 
            * @param actualRepayAmount The amount of cTokenBorrowed underlying to convert into cTokenCollateral tokens 
            * @return (errorCode, number of cTokenCollateral tokens to be seized in a liquidation)
            */
            function liquidateCalculateSeizeTokens(address cTokenBorrowed, address cTokenCollateral, uint actualRepayAmount) external view returns (uint, uint) { 
            /* Read oracle prices for borrowed and collateral markets */    
            uint priceBorrowedMantissa = oracle.getUnderlyingPrice(CToken(cTokenBorrowed));    
            uint priceCollateralMantissa = oracle.getUnderlyingPrice(CToken(cTokenCollateral));    
            if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {        return (uint(Error.PRICE_ERROR), 0);    }    
            /*     * Get the exchange rate and calculate the number of collateral tokens to seize:     
            *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral     
            *  seizeTokens = seizeAmount / exchangeRate     
            *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)     
            */    
            uint exchangeRateMantissa = CToken(cTokenCollateral).exchangeRateStored(); 
            // Note: reverts on error    uint seizeTokens;    Exp memory numerator;       
            //TODO 分子    Exp memory denominator;     
            //TODO 分母    Exp memory ratio;    
            MathError mathErr;    
            (mathErr, numerator) = mulExp(liquidationIncentiveMantissa, priceBorrowedMantissa);    
            //TODO numerator = 借出货币underlying的美金价格 X 清算奖励因子    
            if (mathErr != MathError.NO_ERROR) {        return (uint(Error.MATH_ERROR), 0);    }    
            (mathErr, denominator) = mulExp(priceCollateralMantissa, exchangeRateMantissa);   
            // TODO denominator = 抵押物的美金价格 X 兑换率    
            if (mathErr != MathError.NO_ERROR) {        return (uint(Error.MATH_ERROR), 0);    }    
            (mathErr, ratio) = divExp(numerator, denominator);    
            if (mathErr != MathError.NO_ERROR) {        return (uint(Error.MATH_ERROR), 0);    }    
            //TODO ratio可以理解为清算兑换比例，即 清算者替借款人归还的underlying金额 X ratio = 清算者能获得的借款人的Token数量    
            (mathErr, seizeTokens) = mulScalarTruncate(ratio, actualRepayAmount);    
            if (mathErr != MathError.NO_ERROR) {        return (uint(Error.MATH_ERROR), 0);    }    
            return (uint(Error.NO_ERROR), seizeTokens);}
            //TODO  这里seizeTokens返回的是清算者能获得的cToken数量
            //TODO  清算者能获得的抵押cToken = 清算者归还的underlying金额 X 借款人借出货币的underlying市价 X 清算奖励因子 /(抵押物市价 X 抵押cToken的兑换率)
            /*** Admin Functions ***/
            /**  
            * @notice Sets a new price oracle for the comptroller 
            * @dev Admin function to set a new price oracle  
            * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details) 
            */
            function _setPriceOracle(PriceOracle newOracle) public returns (uint) {   
            //设置价格预言机    
            // Check caller is admin    
            if (msg.sender != admin) {        return fail(Error.UNAUTHORIZED, FailureInfo.SET_PRICE_ORACLE_OWNER_CHECK); //只有admin能设置    }    // Track the old oracle for the comptroller    PriceOracle oldOracle = oracle;    // Set comptroller's oracle to newOracle    oracle = newOracle;    // Emit NewPriceOracle(oldOracle, newOracle)    emit NewPriceOracle(oldOracle, newOracle);  // 记录更新前和更新后的预言机，触发事件    return uint(Error.NO_ERROR);}/**  * @notice Sets the closeFactor used when liquidating borrows  * @dev Admin function to set closeFactor  * @param newCloseFactorMantissa New close factor, scaled by 1e18  * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)  */function _setCloseFactor(uint newCloseFactorMantissa) external returns (uint) {    // Check caller is admin    if (msg.sender != admin) {        return fail(Error.UNAUTHORIZED, FailureInfo.SET_CLOSE_FACTOR_OWNER_CHECK);    }    Exp memory newCloseFactorExp = Exp({mantissa: newCloseFactorMantissa});    Exp memory lowLimit = Exp({mantissa: closeFactorMinMantissa});    if (lessThanOrEqualExp(newCloseFactorExp, lowLimit)) {        return fail(Error.INVALID_CLOSE_FACTOR, FailureInfo.SET_CLOSE_FACTOR_VALIDATION);    }    Exp memory highLimit = Exp({mantissa: closeFactorMaxMantissa});    if (lessThanExp(highLimit, newCloseFactorExp)) {        return fail(Error.INVALID_CLOSE_FACTOR, FailureInfo.SET_CLOSE_FACTOR_VALIDATION);    }    uint oldCloseFactorMantissa = closeFactorMantissa;    closeFactorMantissa = newCloseFactorMantissa;    emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);    return uint(Error.NO_ERROR);}//只有管理员才能修改closeFactor,TODO 且只能在(0.05,0.9)这个开区间之内进行设置,记录修改并触发事件/**  * @notice Sets the collateralFactor for a market  * @dev Admin function to set per-market collateralFactor  * @param cToken The market to set the factor on  * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18  * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)  */function _setCollateralFactor(CToken cToken, uint newCollateralFactorMantissa) external returns (uint) {    // Check caller is admin    if (msg.sender != admin) {        return fail(Error.UNAUTHORIZED, FailureInfo.SET_COLLATERAL_FACTOR_OWNER_CHECK);    }    // Verify market is listed    Market storage market = markets[address(cToken)];    if (!market.isListed) {        return fail(Error.MARKET_NOT_LISTED, FailureInfo.SET_COLLATERAL_FACTOR_NO_EXISTS);    }    //TODO 只有supportMarket的cToken才能设置抵押因子    Exp memory newCollateralFactorExp = Exp({mantissa: newCollateralFactorMantissa});    // Check collateral factor <= 0.9 //TODO 要求抵押因子 <= 0.9    Exp memory highLimit = Exp({mantissa: collateralFactorMaxMantissa});    if (lessThanExp(highLimit, newCollateralFactorExp)) {        return fail(Error.INVALID_COLLATERAL_FACTOR, FailureInfo.SET_COLLATERAL_FACTOR_VALIDATION);    }    // If collateral factor != 0, fail if price == 0 TODO 价格为0而新的抵押因子不为0时会报错    if (newCollateralFactorMantissa != 0 && oracle.getUnderlyingPrice(cToken) == 0) {        return fail(Error.PRICE_ERROR, FailureInfo.SET_COLLATERAL_FACTOR_WITHOUT_PRICE);    }    // Set market's collateral factor to new collateral factor, remember old value    uint oldCollateralFactorMantissa = market.collateralFactorMantissa;    market.collateralFactorMantissa = newCollateralFactorMantissa;    // Emit event with asset, old collateral factor, and new collateral factor    emit NewCollateralFactor(cToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);    return uint(Error.NO_ERROR);}/**  * @notice Sets maxAssets which controls how many markets can be entered  * @dev Admin function to set maxAssets  * @param newMaxAssets New max assets  * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)  */function _setMaxAssets(uint newMaxAssets) external returns (uint) {    // Check caller is admin    if (msg.sender != admin) {        return fail(Error.UNAUTHORIZED, FailureInfo.SET_MAX_ASSETS_OWNER_CHECK);    }    uint oldMaxAssets = maxAssets;    maxAssets = newMaxAssets;    emit NewMaxAssets(oldMaxAssets, newMaxAssets);    return uint(Error.NO_ERROR);}/**  * @notice Sets liquidationIncentive  * @dev Admin function to set liquidationIncentive  * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18  * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)  */function _setLiquidationIncentive(uint newLiquidationIncentiveMantissa) external returns (uint) {    // Check caller is admin    if (msg.sender != admin) {        return fail(Error.UNAUTHORIZED, FailureInfo.SET_LIQUIDATION_INCENTIVE_OWNER_CHECK);    }    // Check de-scaled min <= newLiquidationIncentive <= max TODO 要求清算奖励因子在 [1.0,1.5] 区间内    Exp memory newLiquidationIncentive = Exp({mantissa: newLiquidationIncentiveMantissa});    Exp memory minLiquidationIncentive = Exp({mantissa: liquidationIncentiveMinMantissa});    if (lessThanExp(newLiquidationIncentive, minLiquidationIncentive)) {        return fail(Error.INVALID_LIQUIDATION_INCENTIVE, FailureInfo.SET_LIQUIDATION_INCENTIVE_VALIDATION);    }    Exp memory maxLiquidationIncentive = Exp({mantissa: liquidationIncentiveMaxMantissa});    if (lessThanExp(maxLiquidationIncentive, newLiquidationIncentive)) {        return fail(Error.INVALID_LIQUIDATION_INCENTIVE, FailureInfo.SET_LIQUIDATION_INCENTIVE_VALIDATION);    }    // Save current value for use in log    uint oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;    // Set liquidation incentive to new incentive    liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;    // Emit event with old incentive, new incentive    emit NewLiquidationIncentive(oldLiquidationIncentiveMantissa, newLiquidationIncentiveMantissa);    return uint(Error.NO_ERROR);}/**  * @notice Add the market to the markets mapping and set it as listed  * @dev Admin function to set isListed and add support for the market  * @param cToken The address of the market (token) to list  * @return uint 0=success, otherwise a failure. (See enum Error for details)  */function _supportMarket(CToken cToken) external returns (uint) {    if (msg.sender != admin) {  //只有管理员能进行supportMarket操作        return fail(Error.UNAUTHORIZED, FailureInfo.SUPPORT_MARKET_OWNER_CHECK);    }    if (markets[address(cToken)].isListed) {        //TODO 同一个cToken只能supportMarket一次        return fail(Error.MARKET_ALREADY_LISTED, FailureInfo.SUPPORT_MARKET_EXISTS);    }    cToken.isCToken(); // Sanity check to make sure its really a CToken  //TODO 需了解一下如何判断    markets[address(cToken)] = Market({isListed: true, isComped: false, collateralFactorMantissa: 0});    //TODO 此时是否挖矿初始化为false，抵押因子初始化为0    _addMarketInternal(address(cToken));    emit MarketListed(cToken);    return uint(Error.NO_ERROR);}function _addMarketInternal(address cToken) internal {    for (uint i = 0; i < allMarkets.length; i ++) {        require(allMarkets[i] != CToken(cToken), "market already added");  //TODO 再次检查该cToken是否已经被supportMarket过    }    allMarkets.push(CToken(cToken));  //进入市场}/** * @notice Admin function to change the Pause Guardian * @param newPauseGuardian The address of the new Pause Guardian * @return uint 0=success, otherwise a failure. (See enum Error for details) */function _setPauseGuardian(address newPauseGuardian) public returns (uint) {    //TODO 由管理员来设置守护者    if (msg.sender != admin) {        return fail(Error.UNAUTHORIZED, FailureInfo.SET_PAUSE_GUARDIAN_OWNER_CHECK);    }    // Save current value for inclusion in log    address oldPauseGuardian = pauseGuardian;    // Store pauseGuardian with value newPauseGuardian    pauseGuardian = newPauseGuardian;    // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)    emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);    return uint(Error.NO_ERROR);}function _setMintPaused(CToken cToken, bool state) public returns (bool) {      //暂停存款    require(markets[address(cToken)].isListed, "cannot pause a market that is not listed");  //只能暂停流动性市场中的cToken存款    require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");    //TODO 注意守护者和管理员都可以暂停    require(msg.sender == admin || state == true, "only admin can unpause");    //TODO 只有管理员可以解除暂停，state==true表示要执行暂停操作，false表示要执行借出暂停操作    mintGuardianPaused[address(cToken)] = state;    emit ActionPaused(cToken, "Mint", state);    return state;}function _setBorrowPaused(CToken cToken, bool state) public returns (bool) {  //暂停借款    require(markets[address(cToken)].isListed, "cannot pause a market that is not listed");    require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");    require(msg.sender == admin || state == true, "only admin can unpause");    borrowGuardianPaused[address(cToken)] = state;    emit ActionPaused(cToken, "Borrow", state);    return state;}function _setTransferPaused(bool state) public returns (bool) {    require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");    require(msg.sender == admin || state == true, "only admin can unpause");    //TODO 这个comptroller管理的所有池子都暂停转账    transferGuardianPaused = state;    emit ActionPaused("Transfer", state);    return state;}function _setSeizePaused(bool state) public returns (bool) {    require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");    require(msg.sender == admin || state == true, "only admin can unpause");    //TODO 这个comptroller管理的所有池子都暂停清算获取    seizeGuardianPaused = state;    emit ActionPaused("Seize", state);    return state;}function _become(Unitroller unitroller) public {    require(msg.sender == unitroller.admin(), "only unitroller admin can change brains");    require(unitroller._acceptImplementation() == 0, "change not authorized");}//TODO 只有两个require？ 实际做了哪些操作？//TODO 检查操作者是否是unitroller管理员，以及unitroller的_acceptImplementation()是否为0/** * @notice Checks caller is admin, or this contract is becoming the new implementation */function adminOrInitializing() internal view returns (bool) {    return msg.sender == admin || msg.sender == comptrollerImplementation;}//TODO 在哪里会用到这个方法？/*** Comp Distribution ***//** * @notice Recalculate and update COMP speeds for all COMP markets */function refreshCompSpeeds() public {    require(msg.sender == tx.origin, "only externally owned accounts may refresh speeds");    //TODO 注意只有外部用户才能更新挖矿速率    refreshCompSpeedsInternal();}function refreshCompSpeedsInternal() internal {         //更新挖矿速率    CToken[] memory allMarkets_ = allMarkets;    for (uint i = 0; i < allMarkets_.length; i++) {        CToken cToken = allMarkets_[i];        Exp memory borrowIndex = Exp({mantissa: cToken.borrowIndex()});     //TODO 获得每一个市场的borrowIndex，borrowIndex的含义？        updateCompSupplyIndex(address(cToken));             //更新该市场的存款部分的comSupplyState结构体的指数和区块编号        updateCompBorrowIndex(address(cToken), borrowIndex);    //更新该市场借款部分的comSupplyState结构体的指数和区块编号    }    Exp memory totalUtility = Exp({mantissa: 0});    Exp[] memory utilities = new Exp[](allMarkets_.length);    for (uint i = 0; i < allMarkets_.length; i++) {        CToken cToken = allMarkets_[i];        if (markets[address(cToken)].isComped) {            Exp memory assetPrice = Exp({mantissa: oracle.getUnderlyingPrice(cToken)});            Exp memory utility = mul_(assetPrice, cToken.totalBorrows());   //单个市场借出的总资金数量（含利息） X 基础资产价格            utilities[i] = utility;            totalUtility = add_(totalUtility, utility);     //全部市场的借出的总资金价值（含利息）        }    }    for (uint i = 0; i < allMarkets_.length; i++) {        CToken cToken = allMarkets[i];        uint newSpeed = totalUtility.mantissa > 0 ? mul_(compRate, div_(utilities[i], totalUtility)) : 0;        //TODO 每个池子的挖矿速率按该池子总借出资金量占所有池子的总借出资金量的比例更新        //TODO 注意后面存款和借款部分同时拥有这个挖矿速率        compSpeeds[address(cToken)] = newSpeed;        emit CompSpeedUpdated(cToken, newSpeed);    }}/** * @notice Accrue COMP to the market by updating the supply index * @param cToken The market whose supply index to update */function updateCompSupplyIndex(address cToken) internal {    //TODO 任何改变totalSupply的操作都会触发updateCompSupplyIndex,如mint，redeem,seize,transfer    //TODO 另外claimCan,refreshCanSpeed也会触发updateCompSupplyIndex    CompMarketState storage supplyState = compSupplyState[cToken];    //TODO CompMarketState维护一个结构体，包含上一次更新市场利率指数和区块编号    //TODO compSupplyState维护一个从cToken到ComparketState的映射    uint supplySpeed = compSpeeds[cToken];      //获得该市场当前的挖矿速率    uint blockNumber = getBlockNumber();        //获得当前区块编号    uint deltaBlocks = sub_(blockNumber, uint(supplyState.block));  //获得上次更新至当前区块的间隔区块数    //TODO


        if (deltaBlocks > 0 && supplySpeed > 0) {        uint supplyTokens = CToken(cToken).totalSupply();       
        //获得该市场发行的全部cToken数量        uint compAccrued = mul_(deltaBlocks, supplySpeed);      
        //获得该市场新增的Can币数量        
        //TODO 注意这里用间隔区块数 X 挖矿速率得到了存款部分的新增Can币数量，借款部分的新增Can币数量和这个一样，说明总的挖矿速率是这个CanSpeed的两倍        Double memory ratio = supplyTokens > 0 ? fraction(compAccrued, supplyTokens) : Double({mantissa: 0});        //ratio = 新增挖出的Can币数量 / 该市场cToken的总供应量 ，得到每个cToken新分得的Can币数量        Double memory index = add_(Double({mantissa: supplyState.index}), ratio);        
        //TODO 这个index里保存的是初始cToken当前能分到的Can币数量，是理论上一个cToken当前获得的Can币的最大值        
        compSupplyState[cToken] = CompMarketState({            index: safe224(index.mantissa, "new index exceeds 224 bits"),  
        //TODO 要求index不超过224位，why？ 因为2**224已经很大了            block: safe32(blockNumber, "block number exceeds 32 bits")        });        
        //TODO 保存新的CompMarketeState结构体    } 
        else if (deltaBlocks > 0) {   
        //TODO 如果挖矿速率为0则只更新区块编号，不更新index        
        supplyState.block = safe32(blockNumber, "block number exceeds 32 bits");    }}
        /** 
        * @notice Accrue COMP to the market by updating the borrow index 
        * @param cToken The market whose borrow index to update 
        */function updateCompBorrowIndex(address cToken, Exp memory marketBorrowIndex) internal {    
        // TODO 能触发updateCompBorrowIndex的操作有：borrow,repayBorrow,refreshCompSpeeds    
        // TODO 问题：既然cToken中的borrowIndex()方法可以拿到marketBorrowIndex，为什么还要传入单独的一个marketBorrowIndex?    
        // TODO 除非有时调用这个方法时传入的marketBorrowIndex与从cToken中拿到的数值不一样    
        CompMarketState storage borrowState = compBorrowState[cToken];      
        //获得该市场的borrowState结构体    uint borrowSpeed = compSpeeds[cToken];      
        //获得该市场的挖矿速率    uint blockNumber = getBlockNumber();        
        //获得当前区块编号    uint deltaBlocks = sub_(blockNumber, uint(borrowState.block));      
        //获得上一次更新距当前区块的间隔数    
        if (deltaBlocks > 0 && borrowSpeed > 0) {        uint borrowAmount = div_(CToken(cToken).totalBorrows(), marketBorrowIndex);        
        //TODO 借出数量=借出金额/借出指数？ 需要弄清楚每个变量的含义        
        //TODO 可以反过来理解借出指数 marketBorrowIndex = (总的借出数量+利息)/总的借出数量 ？        
        uint compAccrued = mul_(deltaBlocks, borrowSpeed);  
        //TODO deltaBlocks间隔累计的Can币        
        Double memory ratio = borrowAmount > 0 ? fraction(compAccrued, borrowAmount) : Double({mantissa: 0});        
        Double memory index = add_(Double({mantissa: borrowState.index}), ratio);        
        compBorrowState[cToken] = CompMarketState({            index: safe224(index.mantissa, "new index exceeds 224 bits"),            block: safe32(blockNumber, "block number exceeds 32 bits")        });        
        //TODO 这个index可以理解为借出一个单位能获得的Can币的最大值    } 
        else if (deltaBlocks > 0) {        borrowState.block = safe32(blockNumber, "block number exceeds 32 bits");    }}
        /**
        * @notice Calculate COMP accrued by a supplier and possibly transfer it to them 
        * @param cToken The market in which the supplier is interacting
        * @param supplier The address of the supplier to distribute COMP to 
        */
        function distributeSupplierComp(address cToken, address supplier, bool distributeAll) internal {    CompMarketState storage supplyState = compSupplyState[cToken];  
        //获得这个市场的存款部分的 compMarketState 结构体    Double memory supplyIndex = Double({mantissa: supplyState.index});    
        //获得这个池子的借款部分的供应指数    Double memory supplierIndex = Double({mantissa: compSupplierIndex[cToken][supplier]});    
        //某个supplier在某个cToken池子里上一次剩余的comp币    
        // TODO compSupplierIndex维护的是每个存款者在每个市场的上一次Accrued Can币时的supply index    
        compSupplierIndex[cToken][supplier] = supplyIndex.mantissa;    
        // TODO 先保存这个指数，再更新这个指数    
        if (supplierIndex.mantissa == 0 && supplyIndex.mantissa > 0) {        supplierIndex.mantissa = compInitialIndex;    }    
        // TODO 如果这个存款人的supplierIndex值为0且当前市场的supplyIndex>0，则初始化这个存款者的supplierIndex为 1e36    
        Double memory deltaIndex = sub_(supplyIndex, supplierIndex);    
        //TODO    //TODO 当前市场的指数-用户上一次更新的指数（可能是mint,redeem,seize,transfer操作触发的更新）=用户这次增加的指数    
        uint supplierTokens = CToken(cToken).balanceOf(supplier);       
        //获得用户的cToken数量    uint supplierDelta = mul_(supplierTokens, deltaIndex);      
        //用户新增的Can币数量    uint supplierAccrued = add_(compAccrued[supplier], supplierDelta);    
        // TODO 得到用户累计未领取的Can币数量    
        compAccrued[supplier] = transferComp(supplier, supplierAccrued, distributeAll ? 0 : compClaimThreshold);    
        //TODO distributeAll表示是否全部分发，如果是则全部分发，如果不是则超过临界值threshold才全部分发，返回剩余未领取Cab币数量    
        emit DistributedSupplierComp(CToken(cToken), supplier, supplierDelta, supplyIndex.mantissa); //触发分发存款部分的Can币事件}
        /**
        * @notice Calculate COMP accrued by a borrower and possibly transfer it to them 
        * @dev Borrowers will not begin to accrue until after the first interaction with the protocol.
        * @param cToken The market in which the borrower is interacting
        * @param borrower The address of the borrower to distribute COMP to 
        */
        function distributeBorrowerComp(address cToken, address borrower, Exp memory marketBorrowIndex, bool distributeAll) internal {    CompMarketState storage borrowState = compBorrowState[cToken];   
        //获取借款市场的 CompMarketState    Double memory borrowIndex = Double({mantissa: borrowState.index});  
        //取出市场的计算挖矿的借款的 borrowIndex    
        Double memory borrowerIndex = Double({mantissa: compBorrowerIndex[cToken][borrower]}); 
        //取出borrower上一次的borrow index指数    compBorrowerIndex[cToken][borrower] = borrowIndex.mantissa; 
        //更新borrowIndex指数    
        if (borrowerIndex.mantissa > 0) {        Double memory deltaIndex = sub_(borrowIndex, borrowerIndex); 
        //获取市场的借款指数和借款人上一次的借款指数的指数差        
        uint borrowerAmount = div_(CToken(cToken).borrowBalanceStored(borrower), marketBorrowIndex);        
        //TODO 借款人的欠款余额(包含利息)/市场的借款指数=借款数量        
        uint borrowerDelta = mul_(borrowerAmount, deltaIndex);  
        //借款数量 X 借款指数差 = 挖矿的借款部分数量差        
        uint borrowerAccrued = add_(compAccrued[borrower], borrowerDelta);        
        // TODO 这里的borrowerAccrued就是更新的未领取的借款部分的挖矿所得        
        compAccrued[borrower] = transferComp(borrower, borrowerAccrued, distributeAll ? 0 : compClaimThreshold);        
        emit DistributedBorrowerComp(CToken(cToken), borrower, borrowerDelta, borrowIndex.mantissa);    }}
        /** 
        * @notice Transfer COMP to the user, if they are above the threshold
        * @dev Note: If there is not enough COMP, we do not perform the transfer all.
        * @param user The address of the user to transfer COMP to 
        * @param userAccrued The amount of COMP to (possibly) transfer
        * @return The amount of COMP which was NOT transferred to the user
        */
        function transferComp(address user, uint userAccrued, uint threshold) internal returns (uint) {    
          if (userAccrued >= threshold && userAccrued > 0) {  
          //只有在累计未领取值大于0且大于临界值时才执行领取Can币的操作        
          Comp comp = Comp(getCompAddress());     
          //实例化Can币合约        
          uint compRemaining = comp.balanceOf(address(this));       
          //TODO 注意这里是获得comptroller在Can币合约的余额,所以claim不成功，有可能是因为comptroller中Can币余额不够了        
          if (userAccrued <= compRemaining) {            comp.transfer(user, userAccrued);            return 0;       
          //TODO 注意这里是可以领取完的        
          }    }    return userAccrued;     
          //返回该用户未领取的余额}
          /** 
          * @notice Claim all the comp accrued by holder in all markets 
          * @param holder The address to claim COMP for 
          */
          function claimComp(address holder) public {
          return claimComp(holder, allMarkets);}
          /** 
          * @notice Claim all the comp accrued by holder in the specified markets
          * @param holder The address to claim COMP for 
          * @param cTokens The list of markets to claim COMP in 
          */
          function claimComp(address holder, CToken[] memory cTokens) public {    address[] memory holders = new address[](1);   
          holders[0] = holder;   
          claimComp(holders, cTokens, true, true);}
          /** 
          * @notice Claim all comp accrued by the holders
          * @param holders The addresses to claim COMP for 
          * @param cTokens The list of markets to claim COMP in 
          * @param borrowers Whether or not to claim COMP earned by borrowing
          * @param suppliers Whether or not to claim COMP earned by supplying 
          */
          function claimComp(address[] memory holders, CToken[] memory cTokens, bool borrowers, bool suppliers) public {    
          for (uint i = 0; i < cTokens.length; i++) 
          {        CToken cToken = cTokens[i];        
          require(markets[address(cToken)].isListed, "market must be listed");       
          if (borrowers == true) {            Exp memory borrowIndex = Exp({mantissa: cToken.borrowIndex()});            
          updateCompBorrowIndex(address(cToken), borrowIndex);            
          for (uint j = 0; j < holders.length; j++) {                
          distributeBorrowerComp(address(cToken), holders[j], borrowIndex, true);            }        }       
          if (suppliers == true) {            updateCompSupplyIndex(address(cToken));            
          for (uint j = 0; j < holders.length; j++) {                distributeSupplierComp(address(cToken), holders[j], true);
          }        }    }}
          /*** Comp Distribution Admin ***/
          /** 
          * @notice Set the amount of COMP distributed per block 
          * @param compRate_ The amount of COMP wei per block to distribute
          */
          function _setCompRate(uint compRate_) public {    
          require(adminOrInitializing(), "only admin can change comp rate");    
          uint oldRate = compRate;    
          compRate = compRate_;    
          emit NewCompRate(oldRate, compRate_);    
          refreshCompSpeedsInternal();}
          /** 
          * @notice Add markets to compMarkets, allowing them to earn COMP in the flywheel
          * @param cTokens The addresses of the markets to add 
          */
          function _addCompMarkets(address[] memory cTokens) public {    
          require(adminOrInitializing(), 
          "only admin can add comp market"); 
          for (uint i = 0; i < cTokens.length; i++) {        _addCompMarketInternal(cTokens[i]);    }   
          refreshCompSpeedsInternal();}
          function _addCompMarketInternal(address cToken) internal {    Market storage market = markets[cToken];   
          require(market.isListed == true, "comp market is not listed");   
          require(market.isComped == false, "comp market already added"); 
          //TODO 只能加入一次    
          market.isComped = true;     
          //TODO 启动挖矿    
          emit MarketComped(CToken(cToken), true);    
          if (compSupplyState[cToken].index == 0 && compSupplyState[cToken].block == 0) {    
          //加入市场时初始化comSupplyState        
          compSupplyState[cToken] = CompMarketState({            index: compInitialIndex,            block: safe32(getBlockNumber(), "block number exceeds 32 bits")        });    }    
          if (compBorrowState[cToken].index == 0 && compBorrowState[cToken].block == 0) {    
          //加入市场时初始化comBorrowState        
          compBorrowState[cToken] = CompMarketState({            index: compInitialIndex,            block: safe32(getBlockNumber(), "block number exceeds 32 bits")        });    }}
          /** 
          * @notice Remove a market from compMarkets, preventing it from earning COMP in the flywheel
          * @param cToken The address of the market to drop */function _dropCompMarket(address cToken) public {    
          require(msg.sender == admin, "only admin can drop comp market");    
          Market storage market = markets[cToken];    
          require(market.isComped == true, "market is not a comp market");    
          market.isComped = false;    
          emit MarketComped(CToken(cToken), false);    
          refreshCompSpeedsInternal();    
          //TODO 退出市场时会更新挖矿速率}
          /** 
          * @notice Return all of the markets
          * @dev The automatic getter may be used to access an individual market.
          * @return The list of market addresses 
          */
          function getAllMarkets() public view returns (CToken[] memory) {    
          return allMarkets;}
          function getBlockNumber() public view returns (uint) {    return block.number;}
          /** 
          * @notice Return the address of the COMP token 
          * @return The address of COMP 
          */
          function getCompAddress() public view returns (address) {    return 0x0d14deE0D75D9B2b8cAe378979E5bFca06266cb4;}

}
