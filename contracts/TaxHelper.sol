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

contract TaxHelper {

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

    /* ========== Events ========== */

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiquidity
    );

    /* ========== Stake/Unstake Fee ========== */

    address public LAMBO;
    address public LIQUIDITY_POOL;
    address public CHARITY;
    address public BLACK_HOLE;
    address public TEAM;
    address public DAO_COMMUNITY;
    address public MARKETING;

    /* ========== Stake/Unstake Fee ========== */

    uint256 public TOTAL_FEE = 96969;
    
    uint256 public LAMBO_FEE = 6969;
    uint256 public LIQUIDITY_POOL_FEE = 22200;
    uint256 public DISTRIBUTED_FEE = 42000;
    uint256 public CHARITY_FEE = 6969;
    uint256 public BLACK_HOLE_FEE = 6969;
    uint256 public MARKETING_FEE = 6969;
    uint256 public TEAM_FEE = 4200;
    uint256 public DAO_COMMUNITY_FEE = 690;


    /* ========== Wallet Balance lifetime =========== */

    uint256 public lifetime_lambo = 0;
    uint256 public lifetime_pool = 0;
    uint256 public lifetime_distributed = 0;
    uint256 public lifetime_charity = 0;
    uint256 public lifetime_blackhole = 0;
    uint256 public lifetime_marketing = 0;
    uint256 public lifetime_team = 0;
    uint256 public lifetime_dao = 0;

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

    function calcTotalTax( uint256 _amount ) external virtual returns (uint256) {
        require(msg.sender == staking, "Only Staking Contract");
        uint256 total_fees = 0;
        uint256 distributed_fee = 0;

        total_fees = _amount.mul(TOTAL_FEE).div(1000000);
        distributed_fee = _amount.mul(DISTRIBUTED_FEE).div(1000000);

        BLOCKS.approve(address(staking), BLOCKS.allowance(address(this), address(staking)).add(distributed_fee));
        return total_fees;
    }

    function processTax(uint256 _amount) external returns (uint256) {
        require(msg.sender == staking, "Only Staking Contract");

        uint256 lambo_fee = 0;
        uint256 liquidity_fee = 0;
        uint256 black_hole_fee = 0;
        uint256 distributed_fee = 0;
        uint256 charity_fee = 0;
        uint256 marketing_fee = 0;
        uint256 team_fee = 0;
        uint256 dao_commuinity_fee = 0;

        lambo_fee = _amount.mul(LAMBO_FEE).div(1000000);
        distributed_fee = _amount.mul(DISTRIBUTED_FEE).div(1000000);
        charity_fee = _amount.mul(CHARITY_FEE).div(1000000);
        black_hole_fee = _amount.mul(BLACK_HOLE_FEE).div(1000000);
        team_fee = _amount.mul(TEAM_FEE).div(1000000);
        dao_commuinity_fee = _amount.mul(DAO_COMMUNITY_FEE).div(1000000);

        marketing_fee = _amount.mul(MARKETING_FEE).div(1000000);
        liquidity_fee = _amount.mul(LIQUIDITY_POOL_FEE).div(1000000);

        BLOCKS.safeTransfer(address(LAMBO), lambo_fee);
        BLOCKS.safeTransfer(address(CHARITY), charity_fee);
        BLOCKS.safeTransfer(address(BLACK_HOLE), black_hole_fee);
        BLOCKS.safeTransfer(address(TEAM), team_fee);
        BLOCKS.safeTransfer(address(DAO_COMMUNITY), dao_commuinity_fee);

        swapAndSendFee(marketing_fee, MARKETING);

        swapAndLiquify(liquidity_fee);

        lifetime_lambo = lifetime_lambo.add(lambo_fee);
        lifetime_distributed = lifetime_distributed.add(distributed_fee);
        lifetime_charity = lifetime_charity.add(charity_fee);
        lifetime_blackhole = lifetime_blackhole.add(black_hole_fee);
        lifetime_team = lifetime_team.add(team_fee);
        lifetime_dao = lifetime_dao.add(dao_commuinity_fee);
        lifetime_marketing = lifetime_marketing.add(marketing_fee);
        lifetime_pool = lifetime_pool.add(liquidity_fee);

        distributorAmount = distributorAmount.add(distributed_fee);

        return lifetime_lambo;
    }

    function getRewardAmount(uint256 _amount) external returns(uint256) {
        require(msg.sender == staking, "Only Staking Contract");

        uint256 rewardAmount;

        rewardAmount = _amount.div(BLOCKS.balanceOf(address(staking))).mul(distributorAmount);
        distributorAmount = distributorAmount.sub(rewardAmount);

        return rewardAmount;
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
        (bool success, ) = feeAddress.call{value: newBalance}("");
        require(success, "BLOCKS: Payment to marketing wallet failed");
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

        emit SwapAndLiquify(half, newBalance, otherHalf);
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
}