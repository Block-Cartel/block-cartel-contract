// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "./libraries/SafeMath.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/Address.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IBLOCKS.sol";
import "./interfaces/IsBLOCKS.sol";

contract TaxHelperV2 {

    using SafeMath for uint256;
    using SafeERC20 for IBLOCKS;
    using SafeERC20 for IsBLOCKS;
    using SafeERC20 for IERC20;
    using Address for address;

    address public immutable staking;

    address public immutable DAI;
    IBLOCKS public immutable BLOCKS;
    IsBLOCKS public immutable sBLOCKS;

    uint256 private distributorAmount = 0;

    IUniswapV2Router02 private _uniswapV2Router;
    address private _uniswapV2Pair;

    bool public createdPool;

    /* ========== Stake/Unstake Fee ========== */

    address public LAMBO;
    address public LIQUIDITY_POOL;
    address public CHARITY;
    address public BLACK_HOLE;
    address public TEAM;
    address public DAO_COMMUNITY;
    address payable public MARKETING;

    /* ========== Stake/Unstake Fee ========== */
    
    uint256 public LAMBO_FEE = 7187;
    uint256 public LIQUIDITY_POOL_FEE = 22895;
    uint256 public DISTRIBUTED_FEE = 43314;
    uint256 public CHARITY_FEE = 7187;
    uint256 public BLACK_HOLE_FEE = 7187;
    uint256 public MARKETING_FEE = 7187;
    uint256 public TEAM_FEE = 4331;
    uint256 public DAO_COMMUNITY_FEE = 712;


    /* ========== Wallet Balance lifetime =========== */

    uint256 public lifetime_lambo = 0;
    uint256 public lifetime_pool = 0;
    uint256 public lifetime_distributed = 0;
    uint256 public lifetime_charity = 0;
    uint256 public lifetime_blackhole = 0;
    uint256 public lifetime_marketing = 0;
    uint256 public lifetime_team = 0;
    uint256 public lifetime_dao = 0;

    /* ========== Stake/Unstake Fee ========== */

    uint256 public entry_tax = 420;
    uint256 public entry_tax_interval = 42;

    uint256 public exit_tax = 669;
    uint256 public exit_tax_interval = 69;

    struct TaxInfo {
        uint256 epoch_number;
        uint256 refundAmount;
        uint256 amount;
    }

    mapping (address => TaxInfo[]) public taxTracker;
    mapping (address => uint256) public stakeNumber;

    event TransferTax(address account, uint256 blockNumber, uint256 blockTime, uint256 isEntry, uint256 amount, uint256 cal_entry_tax, uint256 cal_exit_tax, uint256 refundAmount);

    constructor (
        address _DAI,
        address _staking,
        address _BLOCKS,
        address _sBLOCKS,
        address _LAMBO,
        address _LIQUIDITY,
        address _CHARITY,
        address _BLACK_HOLE,
        address _MARKETING,
        address _TEAM,
        address _DAO_COMMUNITY
    ) {

        require( _DAI != address(0) );
        DAI = _DAI;

        require( _staking != address(0) );
        staking = _staking;
        require( _BLOCKS != address(0) );
        BLOCKS = IBLOCKS(_BLOCKS);
        require( _sBLOCKS != address(0) );
        sBLOCKS = IsBLOCKS(_sBLOCKS);

        require( _LAMBO != address(0) );
        LAMBO = _LAMBO;

        require( _LIQUIDITY != address(0) );
        LIQUIDITY_POOL = _LIQUIDITY;

        require( _CHARITY != address(0) );
        CHARITY = _CHARITY;

        require( _BLACK_HOLE != address(0) );
        BLACK_HOLE = _BLACK_HOLE;

        require( _TEAM != address(0) );
        TEAM = _TEAM;

        require( _DAO_COMMUNITY != address(0) );
        DAO_COMMUNITY = _DAO_COMMUNITY;

        require( _MARKETING != address(0) );
        MARKETING = payable(_MARKETING);

        createdPool = false;
    }

    function createPairAndLiquidity(uint256 tokenAmount, uint256 daiAmount) public {

        require(!createdPool, "already created");
        // init uniswap

        _uniswapV2Router = IUniswapV2Router02(
            0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
        );

        // get currency pair
        address pair = IUniswapV2Factory(_uniswapV2Router.factory()).getPair(
            address(DAI),
            address(BLOCKS)
        );

        // pair not yet created - create pair
        if (pair == address(0)) {
            _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
                .createPair(address(DAI), address(BLOCKS));
        } else {
            _uniswapV2Pair = pair;
        }

        createdPool = true;

        addLiquidity(tokenAmount, daiAmount);
    }

    function calcTotalTax( uint256 _amount, address _to, uint256 _epoch_number, uint256 isEntry ) external returns (uint256) {
        require(msg.sender == staking, "Only Staking Contract");

        uint256 amount = _amount;
        uint256 epoch_number = _epoch_number;

        uint256 stakeInterval;

        uint256 cal_exit_tax;
        uint256 reduction_exit_tax;
        uint256 cal_refund_amount;

        uint256 cal_entry_tax;

        uint256 returnValue;

        if (stakeNumber[_to] != 0) {
            stakeInterval = epoch_number - stakeNumber[_to];
        } else {
            stakeInterval = 0;
            stakeNumber[_to] = _epoch_number;
        }

        cal_entry_tax = amount * entry_tax / 10000;


        // reduction_exit_tax = amount * exit_tax / 10000 * stakeInterval * 7 / 24 / exit_tax_interval;
        // if (reduction_exit_tax >= amount * exit_tax / 10000) {
        //     reduction_exit_tax = amount * exit_tax / 10000;
        // }
        // cal_exit_tax = amount * exit_tax / 10000 - reduction_exit_tax;


        (cal_exit_tax, cal_refund_amount) = calExitTaxAndRefundAmount(_to, amount, epoch_number);

        if (isEntry == 1) {
            taxTracker[_to].push(
                TaxInfo({
                    epoch_number: epoch_number,
                    refundAmount: cal_entry_tax,
                    amount: amount
                })
            );
            returnValue = cal_entry_tax;
        } else {

            processRefund(_to, cal_refund_amount);

            delete stakeNumber[_to];

            returnValue = cal_exit_tax;
        }

        emit TransferTax(_to, block.number, block.timestamp, isEntry, amount, cal_entry_tax, cal_exit_tax, cal_refund_amount);

        return returnValue;
    }

    function calExitTaxAndRefundAmount(address _to, uint256 _amount, uint256 _epoch_number) internal view returns (uint256, uint256) {
        TaxInfo[] memory info = taxTracker[_to];

        uint256 totalRefund;
        uint256 totalExitTax;
        uint256 stakeInterval;
        uint256 refund;
        uint256 exitTax;

        uint256 amount;
        amount = _amount;

        uint256 reduction_exit_tax;

        for (uint256 i = 0; i < info.length; i ++) {
            if (info[i].amount == 0) continue;
            stakeInterval = _epoch_number - info[i].epoch_number;
            if (info[i].amount > amount) {
                if (stakeInterval * 7 / 24 > exit_tax_interval) {
                    refund = info[i].refundAmount * (stakeInterval * 7 / 24 - exit_tax_interval) / entry_tax_interval;
                    if (refund >= info[i].refundAmount) {
                        refund = info[i].refundAmount;
                    }
                    refund = refund * amount / info[i].amount; 
                    totalRefund = totalRefund.add(refund);
                }

                reduction_exit_tax = amount * exit_tax / 10000 * stakeInterval * 7 / 24 / exit_tax_interval;
                if (reduction_exit_tax >= amount * exit_tax / 10000) {
                    reduction_exit_tax = amount * exit_tax / 10000;
                }
                exitTax = amount * exit_tax / 10000 - reduction_exit_tax;
                totalExitTax = totalExitTax.add(exitTax);

                info[i].refundAmount = info[i].refundAmount - refund;
                info[i].amount = info[i].amount.sub(amount);
                break;
            } else {
                amount = amount.sub(info[i].amount);
                if (stakeInterval * 7 / 24 > exit_tax_interval) {
                    refund = info[i].refundAmount * (stakeInterval * 7 / 24 - exit_tax_interval) / entry_tax_interval;
                    if (refund >= info[i].refundAmount) {
                        refund = info[i].refundAmount;
                    }
                    totalRefund = totalRefund.add(refund);
                }

                reduction_exit_tax = info[i].amount * exit_tax / 10000 * stakeInterval * 7 / 24 / exit_tax_interval;
                if (reduction_exit_tax >= info[i].amount * exit_tax / 10000) {
                    reduction_exit_tax = info[i].amount * exit_tax / 10000;
                }
                exitTax = info[i].amount * exit_tax / 10000 - reduction_exit_tax;
                totalExitTax = totalExitTax.add(exitTax);
    
                info[i].amount = 0;
            }
        }

        // for (uint256 i = 0; i < infos.length; i++) {
        //     stakeInterval = _epoch_number - infos[i].epoch_number;
        //     if (stakeInterval * 7 / 24 > exit_tax_interval) {
        //         refund = infos[i].refundAmount * (stakeInterval * 7 / 24 - exit_tax_interval) / entry_tax_interval;
        //         if (refund >= infos[i].refundAmount) {
        //             refund = infos[i].refundAmount;
        //         }
        //         totalRefund = totalRefund.add(refund);
        //     }
        // }
        return (totalExitTax, totalRefund);
    }

    function removeTaxTracker(address _to) external {
        delete taxTracker[_to];
    }

    function processEntityTax() external {
        require(msg.sender == staking, "Only Staking Contract");

        uint256 amount = BLOCKS.balanceOf(address(this));

        uint256 lambo_fee = 0;
        uint256 liquidity_fee = 0;
        uint256 black_hole_fee = 0;
        uint256 distributed_fee = 0;
        uint256 charity_fee = 0;
        uint256 marketing_fee = 0;
        uint256 team_fee = 0;
        uint256 dao_commuinity_fee = 0;

        lambo_fee = amount.mul(LAMBO_FEE).div(100000);
        distributed_fee = amount.mul(DISTRIBUTED_FEE).div(100000);
        charity_fee = amount.mul(CHARITY_FEE).div(100000);
        black_hole_fee = amount.mul(BLACK_HOLE_FEE).div(100000);
        team_fee = amount.mul(TEAM_FEE).div(100000);
        dao_commuinity_fee = amount.mul(DAO_COMMUNITY_FEE).div(100000);

        marketing_fee = amount.mul(MARKETING_FEE).div(100000);
        liquidity_fee = amount.mul(LIQUIDITY_POOL_FEE).div(100000);

        BLOCKS.safeTransfer(address(LAMBO), lambo_fee);
        BLOCKS.safeTransfer(address(CHARITY), charity_fee);
        BLOCKS.safeTransfer(address(BLACK_HOLE), black_hole_fee);
        BLOCKS.safeTransfer(address(TEAM), team_fee);
        BLOCKS.safeTransfer(address(DAO_COMMUNITY), dao_commuinity_fee);
        BLOCKS.safeTransfer(address(staking), distributed_fee);
        BLOCKS.safeTransfer(address(MARKETING), marketing_fee);
        BLOCKS.safeTransfer(address(LIQUIDITY_POOL), liquidity_fee);

        // swapAndSendFee(marketing_fee, MARKETING);

        // swapAndLiquify(liquidity_fee);

        lifetime_lambo = lifetime_lambo.add(lambo_fee);
        lifetime_distributed = lifetime_distributed.add(distributed_fee);
        lifetime_charity = lifetime_charity.add(charity_fee);
        lifetime_blackhole = lifetime_blackhole.add(black_hole_fee);
        lifetime_team = lifetime_team.add(team_fee);
        lifetime_dao = lifetime_dao.add(dao_commuinity_fee);
        lifetime_marketing = lifetime_marketing.add(marketing_fee);
        lifetime_pool = lifetime_pool.add(liquidity_fee);
    }

    function processRefund(address _to, uint256 refundAmount) internal {
        require(msg.sender == staking, "Only Staking Contract");

        uint256 lambo_refund = 0;
        uint256 distributed_refund = 0;
        uint256 charity_refund = 0;
        uint256 black_hole_refund = 0;
        uint256 team_refund = 0;
        uint256 dao_commuinity_refund = 0;
        uint256 marketing_refund = 0;
        uint256 liquidity_refund = 0;
        uint256 total_refund;

        lambo_refund = refundAmount.mul(LAMBO_FEE).div(100000);
        distributed_refund = refundAmount.mul(DISTRIBUTED_FEE).div(100000);
        charity_refund = refundAmount.mul(CHARITY_FEE).div(100000);
        black_hole_refund = refundAmount.mul(BLACK_HOLE_FEE).div(100000);
        team_refund = refundAmount.mul(TEAM_FEE).div(100000);
        dao_commuinity_refund = refundAmount.mul(DAO_COMMUNITY_FEE).div(100000);

        marketing_refund = refundAmount.mul(MARKETING_FEE).div(100000);
        liquidity_refund = refundAmount.mul(LIQUIDITY_POOL_FEE).div(100000);

        total_refund = total_refund.add(lambo_refund);
        total_refund = total_refund.add(distributed_refund);
        total_refund = total_refund.add(charity_refund);
        total_refund = total_refund.add(black_hole_refund);
        total_refund = total_refund.add(team_refund);
        total_refund = total_refund.add(dao_commuinity_refund);
        total_refund = total_refund.add(marketing_refund);
        total_refund = total_refund.add(liquidity_refund);

        BLOCKS.safeTransferFrom(address(LAMBO), address(this), lambo_refund);
        BLOCKS.safeTransferFrom(address(CHARITY), address(this), charity_refund);
        BLOCKS.safeTransferFrom(address(BLACK_HOLE), address(this), black_hole_refund);
        BLOCKS.safeTransferFrom(address(TEAM), address(this), team_refund);
        BLOCKS.safeTransferFrom(address(DAO_COMMUNITY), address(this), dao_commuinity_refund);
        BLOCKS.safeTransferFrom(address(staking), address(this), distributed_refund);
        BLOCKS.safeTransferFrom(address(MARKETING), address(this), marketing_refund);
        BLOCKS.safeTransferFrom(address(LIQUIDITY_POOL), address(this), liquidity_refund);

        BLOCKS.safeTransfer(_to, total_refund);
    }

    function getTaxStats()
    external view returns (
        uint256 _lifetime_lambo,
        uint256 _lifetime_pool,
        uint256 _lifetime_distributed,
        uint256 _lifetime_charity,
        uint256 _lifetime_blackhole,
        uint256 _lifetime_marketing,
        uint256 _lifetime_team,
        uint256 _lifetime_dao,
        uint256 _current_lambo,
        uint256 _current_charity,
        uint256 _current_marketing,
        uint256 _current_dao
    ) {
        _lifetime_lambo = lifetime_lambo;
        _lifetime_pool = lifetime_pool;
        _lifetime_distributed = lifetime_distributed;
        _lifetime_charity = lifetime_charity;
        _lifetime_blackhole = lifetime_blackhole;
        _lifetime_marketing = lifetime_marketing;
        _lifetime_team = lifetime_team;
        _lifetime_dao = lifetime_dao;
        _current_lambo = BLOCKS.balanceOf(LAMBO);
        _current_charity = BLOCKS.balanceOf(CHARITY);
        _current_marketing = BLOCKS.balanceOf(MARKETING);
        _current_dao = BLOCKS.balanceOf(DAO_COMMUNITY);
    }

    /**
     * @dev function returns marketing wallet address
     */
    function getMarketingAddress() external view returns (address) {
        return MARKETING;
    }

    /**
     * @dev funcction is swaps BETS in the smart contract(tax) to BNB
     */
    function swapTokens(uint256 tokenAmount) private returns (uint256) {
        uint256 initBalance = IERC20(DAI).balanceOf(address(this)); // contract initial balance

        // uniswap token pair path == BETS -> WBNB
        address[] memory path = new address[](2);
        path[0] = address(BLOCKS);
        path[1] = address(DAI);

        BLOCKS.approve(address(_uniswapV2Router), tokenAmount);

        // make the swap
        _uniswapV2Router.swapExactTokensForTokens(
            tokenAmount,
            0, // any amount of BNB
            path,
            address(this),
            block.timestamp
        );

        return (IERC20(DAI).balanceOf(address(this)) - initBalance);
    }

    function swapAndSendFee(uint256 tokens, address feeAddress) private {
        uint256 newBalance = swapTokens(tokens);
        // (bool success, ) = feeAddress.call{value: newBalance}("");
        IERC20(DAI).transfer(MARKETING, newBalance);
        // require(success, "BLOCKS: Payment to marketing wallet failed");
    }

    function swapAndLiquify(uint256 tokens) private {
        // split the contract balance into halves
        uint256 half = tokens / 2;
        uint256 otherHalf = tokens - half;

        // swap tokens for DAI
        uint256 newBalance = swapTokens(half);

        if (createdPool) {
            // add liquidity to uniswap
            addLiquidity(otherHalf, newBalance);
        } else {
            createPairAndLiquidity(otherHalf, newBalance);
        }
    }

    function addLiquidity(uint256 tokenAmount, uint256 daiAmount) private {
        // approve token transfer to cover all possible scenarios
        BLOCKS.approve(address(_uniswapV2Router), tokenAmount);
        IERC20(DAI).approve(address(_uniswapV2Router), daiAmount);

        // add the liquidity
        (, uint256 daiFromLiquidity, ) = _uniswapV2Router.addLiquidity(address(BLOCKS), address(DAI), tokenAmount, daiAmount, 0, 0, address(MARKETING), block.timestamp);
        if (daiAmount - daiFromLiquidity > 0)
            IERC20(DAI).safeTransfer(address(MARKETING), daiAmount - daiFromLiquidity);
    }

    function getPairAddress() public view returns (address) {
        return _uniswapV2Pair;
    }

    function setWalletAddress(address _LAMBO,address  _LIQUIDITY,address  _CHARITY,address  _BLACK_HOLE,address  _MARKETING,address  _TEAM,address  _DAO_COMMUNITY) external {
        require( _LAMBO != address(0) );
        LAMBO = _LAMBO;

        require( _LIQUIDITY != address(0) );
        LIQUIDITY_POOL = _LIQUIDITY;

        require( _CHARITY != address(0) );
        CHARITY = _CHARITY;

        require( _BLACK_HOLE != address(0) );
        BLACK_HOLE = _BLACK_HOLE;

        require( _TEAM != address(0) );
        TEAM = _TEAM;

        require( _DAO_COMMUNITY != address(0) );
        DAO_COMMUNITY = _DAO_COMMUNITY;

        require( _MARKETING != address(0) );
        MARKETING = payable(_MARKETING);
    }

    function setTaxFee(uint256 _LAMBO_FEE,uint256  _LIQUIDITY_POOL_FEE,uint256  _DISTRIBUTED_FEE,uint256  _CHARITY_FEE,uint256  _BLACK_HOLE_FEE,uint256  _MARKETING_FEE,uint256  _TEAM_FEE,uint256  _DAO_COMMUNITY_FEE) external {
        LAMBO_FEE = _LAMBO_FEE;
        LIQUIDITY_POOL_FEE = _LIQUIDITY_POOL_FEE;
        DISTRIBUTED_FEE = _DISTRIBUTED_FEE;
        CHARITY_FEE = _CHARITY_FEE;
        BLACK_HOLE_FEE = _BLACK_HOLE_FEE;
        MARKETING_FEE = _MARKETING_FEE;
        TEAM_FEE = _TEAM_FEE;
        DAO_COMMUNITY_FEE = _DAO_COMMUNITY_FEE;
    }
}