// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.7.5;

import "./libraries/SafeMath.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/Address.sol";

import "./interfaces/IERC20.sol";
import "./interfaces/IERC20Metadata.sol";
import "./interfaces/IBLOCKS.sol";
import "./interfaces/IsBLOCKS.sol";
import "./interfaces/IBondingCalculator.sol";
import "./interfaces/ITreasury.sol";

import "./types/BLOCKSAccessControlled.sol";

contract BLOCKSTreasury is BLOCKSAccessControlled, ITreasury {
    /* ========== DEPENDENCIES ========== */

    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    /* ========== EVENTS ========== */

    event Deposit(address indexed token, uint256 amount, uint256 value);
    event Withdrawal(address indexed token, uint256 amount, uint256 value);
    event CreateDebt(address indexed debtor, address indexed token, uint256 amount, uint256 value);
    event RepayDebt(address indexed debtor, address indexed token, uint256 amount, uint256 value);
    event Managed(address indexed token, uint256 amount);
    event ReservesAudited(uint256 indexed totalReserves);
    event Minted(address indexed caller, address indexed recipient, uint256 amount);
    event PermissionQueued(STATUS indexed status, address queued);
    event Permissioned(address addr, STATUS indexed status, bool result);

    /* ========== DATA STRUCTURES ========== */

    enum STATUS {
        RESERVEDEPOSITOR,
        RESERVESPENDER,
        RESERVETOKEN,
        RESERVEMANAGER,
        LIQUIDITYDEPOSITOR,
        LIQUIDITYTOKEN,
        LIQUIDITYMANAGER,
        DEBTOR,
        REWARDMANAGER,
        SBLOCKS
    }

    struct Queue {
        STATUS managing;
        address toPermit;
        address calculator;
        uint256 timelockEnd;
        bool nullify;
        bool executed;
    }

    /* ========== STATE VARIABLES ========== */

    IBLOCKS immutable BLOCKS;
    IsBLOCKS public sBLOCKS;

    mapping(STATUS => address[]) public registry;
    mapping(STATUS => mapping(address => bool)) public permissions;
    mapping(address => address) public bondCalculator;

    mapping(address => uint256) public debtorBalance;

    uint256 public totalReserves;
    uint256 public totalDebt;

    Queue[] public permissionQueue;
    uint256 public immutable blocksNeededForQueue;

    bool public onChainGoverned;
    uint256 public onChainGovernanceTimelock;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _BLOCKS,
        uint256 _timelock,
        address _authority
    ) BLOCKSAccessControlled(IBLOCKSAuthority(_authority)) {
        require(_BLOCKS != address(0), "Zero address: BLOCKS");
        BLOCKS = IBLOCKS(_BLOCKS);

        blocksNeededForQueue = _timelock;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
        @notice allow approved address to deposit an asset for BLOCKS
        @param _amount uint
        @param _token address
        @param _profit uint
        @return send_ uint
     */
    function deposit(
        uint256 _amount,
        address _token,
        uint256 _profit
    ) external override returns (uint256 send_) {
        if (permissions[STATUS.RESERVETOKEN][_token]) {
            require(permissions[STATUS.RESERVEDEPOSITOR][msg.sender], "Not approved");
        } else if (permissions[STATUS.LIQUIDITYTOKEN][_token]) {
            require(permissions[STATUS.LIQUIDITYDEPOSITOR][msg.sender], "Not approved");
        } else {
            revert("neither reserve nor liquidity token");
        }

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 value = tokenValue(_token, _amount);
        // mint BLOCKS needed and store amount of rewards for distribution
        send_ = value.sub(_profit);
        BLOCKS.mint(msg.sender, send_);

        totalReserves = totalReserves.add(value);

        emit Deposit(_token, _amount, value);
    }

    /**
        @notice allow approved address to burn BLOCKS for reserves
        @param _amount uint
        @param _token address
     */
    function withdraw(uint256 _amount, address _token) external override {
        require(permissions[STATUS.RESERVETOKEN][_token], "Not accepted"); // Only reserves can be used for redemptions
        require(permissions[STATUS.RESERVESPENDER][msg.sender], "Not approved");

        uint256 value = tokenValue(_token, _amount);
        BLOCKS.burnFrom(msg.sender, value);

        totalReserves = totalReserves.sub(value);

        IERC20(_token).safeTransfer(msg.sender, _amount);

        emit Withdrawal(_token, _amount, value);
    }

    /**
        @notice allow approved address to borrow reserves
        @param _amount uint
        @param _token address
     */
    function incurDebt(uint256 _amount, address _token) external override {
        require(permissions[STATUS.DEBTOR][msg.sender], "Not approved");
        require(permissions[STATUS.RESERVETOKEN][_token], "Not accepted");

        uint256 value = tokenValue(_token, _amount);
        require(value != 0, "Invalid output token");

        uint256 availableDebt = sBLOCKS.balanceOf(msg.sender).sub(sBLOCKS.getdebtBalances(msg.sender));
        require(value <= availableDebt, "Exceeds debt limit");

        sBLOCKS.changeDebt(value, msg.sender, true);
        totalDebt = totalDebt.add(value);

        totalReserves = totalReserves.sub(value);

        IERC20(_token).safeTransfer(msg.sender, _amount);

        emit CreateDebt(msg.sender, _token, _amount, value);
    }

    /**
        @notice allow approved address to repay borrowed reserves with reserves
        @param _amount uint
        @param _token address
     */
    function repayDebtWithReserve(uint256 _amount, address _token) external override {
        require(permissions[STATUS.DEBTOR][msg.sender], "Not approved");
        require(permissions[STATUS.RESERVETOKEN][_token], "Not accepted");

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 value = tokenValue(_token, _amount);
        sBLOCKS.changeDebt(value, msg.sender, false);
        totalDebt = totalDebt.sub(value);

        totalReserves = totalReserves.add(value);

        emit RepayDebt(msg.sender, _token, _amount, value);
    }

    /**
        @notice allow approved address to repay borrowed reserves with BLOCKS
        @param _amount uint
     */
    function repayDebtWithBLOCKS(uint256 _amount) external {
        require(permissions[STATUS.DEBTOR][msg.sender], "Not approved");

        BLOCKS.burnFrom(msg.sender, _amount);

        sBLOCKS.changeDebt(_amount, msg.sender, false);
        totalDebt = totalDebt.sub(_amount);

        emit RepayDebt(msg.sender, address(BLOCKS), _amount, _amount);
    }

    /**
        @notice allow approved address to withdraw assets
        @param _token address
        @param _amount uint
     */
    function manage(address _token, uint256 _amount) external override {
        if (permissions[STATUS.LIQUIDITYTOKEN][_token]) {
            require(permissions[STATUS.LIQUIDITYMANAGER][msg.sender], "Not approved");
        } else {
            require(permissions[STATUS.RESERVEMANAGER][msg.sender], "Not approved");
        }
        if( permissions[STATUS.RESERVETOKEN][_token] || permissions[STATUS.LIQUIDITYTOKEN][_token]) {
            uint256 value = tokenValue(_token, _amount);
            require(value <= excessReserves(), "Insufficient reserves");
            totalReserves = totalReserves.sub(value);
        } 

        IERC20(_token).safeTransfer(msg.sender, _amount);

        emit Managed(_token, _amount);
    }

    /**
        @notice mint new BLOCKS using excess reserves
     */
    function mint(address _recipient, uint256 _amount) external override {
        require(permissions[STATUS.REWARDMANAGER][msg.sender], "Not approved");
        // require(_amount <= excessReserves(), "Insufficient reserves");

        BLOCKS.mint(_recipient, _amount);

        emit Minted(msg.sender, _recipient, _amount);
    }

    /* ========== MANAGERIAL FUNCTIONS ========== */

    /**
        @notice takes inventory of all tracked assets
        @notice always consolidate to recognized reserves before audit
     */
    function auditReserves() external onlyGovernor {
        uint256 reserves;
        address[] memory reserveToken = registry[STATUS.RESERVETOKEN];
        for (uint256 i = 0; i < reserveToken.length; i++) {
            if(permissions[STATUS.RESERVETOKEN][reserveToken[i]]) {
                reserves = reserves.add(tokenValue(reserveToken[i], IERC20(reserveToken[i]).balanceOf(address(this))));
            }
        }
        address[] memory liquidityToken = registry[STATUS.LIQUIDITYTOKEN];
        for (uint256 i = 0; i < liquidityToken.length; i++) {
            if(permissions[STATUS.LIQUIDITYTOKEN][liquidityToken[i]]) {
                reserves = reserves.add(tokenValue(liquidityToken[i], IERC20(liquidityToken[i]).balanceOf(address(this))));
            }
        }
        totalReserves = reserves;
        emit ReservesAudited(reserves);
    }

    /**
     * @notice enable permission from queue
     * @param _status STATUS
     * @param _address address
     * @param _calculator address
     */
    function enable(
        STATUS _status,
        address _address,
        address _calculator
    ) external onlyGovernor {
        // require(onChainGoverned, "OCG Not Enabled: Use queueTimelock");
        if (_status == STATUS.SBLOCKS) {
            sBLOCKS = IsBLOCKS(_address);
        } else {
            permissions[_status][_address] = true;

            if (_status == STATUS.LIQUIDITYTOKEN) {
                bondCalculator[_address] = _calculator;
            }

            (bool registered, ) = indexInRegistry(_address, _status);
            if (!registered) {
                registry[_status].push(_address);

                if (_status == STATUS.LIQUIDITYTOKEN) {
                    (bool reg, uint256 index) = indexInRegistry(_address, STATUS.RESERVETOKEN);
                    if (reg) {
                        delete registry[STATUS.RESERVETOKEN][index];
                    }
                } else if (_status == STATUS.RESERVETOKEN) {
                    (bool reg, uint256 index) = indexInRegistry(_address, STATUS.LIQUIDITYTOKEN);
                    if (reg) {
                        delete registry[STATUS.LIQUIDITYTOKEN][index];
                    }
                }
            }
        }
        emit Permissioned(_address, _status, true);
    }

    /**
     * @notice check if registry contains address
     * @return uint
     */
    function indexInRegistry(address _address, STATUS _status) public view returns (bool, uint256) {
        address[] memory entries = registry[_status];
        for (uint256 i = 0; i < entries.length; i++) {
            if (_address == entries[i]) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    /**
     *  @notice disable permission from address
     *  @param _status STATUS
     *  @param _toDisable address
     */
    function disable(STATUS _status, address _toDisable) external onlyGovernor {
        permissions[_status][_toDisable] = false;
        emit Permissioned(_toDisable, _status, false);
    }

    /* ========== TIMELOCKED FUNCTIONS ========== */

    // functions are used prior to enabling on-chain governance

    /**
        @notice queue address to receive permission
        @param _status STATUS
        @param _address address
     */
    function queueTimelock(
        STATUS _status,
        address _address,
        address _calculator
    ) external onlyGovernor {
        require(_address != address(0));
        require(!onChainGoverned, "OCG Enabled: Use enable");

        uint256 timelock = block.number.add(blocksNeededForQueue);
        if (_status == STATUS.RESERVEMANAGER || _status == STATUS.LIQUIDITYMANAGER) {
            timelock = block.number.add(blocksNeededForQueue.mul(2));
        }
        permissionQueue.push(
            Queue({
                managing: _status, 
                toPermit: _address, 
                calculator: _calculator, 
                timelockEnd: timelock, 
                nullify: false, 
                executed: false
            })
        );
        emit PermissionQueued(_status, _address);
    }

    /**
     *  @notice enable queued permission
     *  @param _index uint
     */
    function execute(uint256 _index) external onlyGovernor {
        require(!onChainGoverned);

        Queue memory info = permissionQueue[_index];

        require(!info.nullify, "Action has been nullified");
        require(!info.executed, "Action has already been executed");
        require(block.number >= info.timelockEnd, "Timelock not complete");

        if (info.managing == STATUS.SBLOCKS) {
            // 9
            sBLOCKS = IsBLOCKS(info.toPermit);
        } else {
            permissions[info.managing][info.toPermit] = true;

            if (info.managing == STATUS.LIQUIDITYTOKEN) {
                bondCalculator[info.toPermit] = info.calculator;
            }
            (bool registered, ) = indexInRegistry(info.toPermit, info.managing);
            if (!registered) {
                registry[info.managing].push(info.toPermit);

                if (info.managing == STATUS.LIQUIDITYTOKEN) {
                    (bool reg, uint256 index) = indexInRegistry(info.toPermit, STATUS.RESERVETOKEN);
                    if (reg) {
                        delete registry[STATUS.RESERVETOKEN][index];
                    }
                } else if (info.managing == STATUS.RESERVETOKEN) {
                    (bool reg, uint256 index) = indexInRegistry(info.toPermit, STATUS.LIQUIDITYTOKEN);
                    if (reg) {
                        delete registry[STATUS.LIQUIDITYTOKEN][index];
                    }
                }
            }
        }
        permissionQueue[_index].executed = true;
        emit Permissioned(info.toPermit, info.managing, true);
    }

    /**
     * @notice cancel timelocked action
     * @param _index uint
     */
    function nullify(uint256 _index) external onlyGovernor {
        permissionQueue[_index].nullify = true;
    }

    /**
     * @notice disables timelocked functions
     */
    function enableOnChainGovernance() external onlyGovernor {
        require(!onChainGoverned, "OCG already enabled");
        if (onChainGovernanceTimelock != 0 && onChainGovernanceTimelock <= block.number) {
            onChainGoverned = true;
        } else {
            onChainGovernanceTimelock = block.number.add(blocksNeededForQueue.mul(7)); // 7-day timelock
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
        @notice returns excess reserves not backing tokens
        @return uint
     */
    function excessReserves() public view override returns (uint256) {
        return totalReserves.sub(BLOCKS.totalSupply().sub(totalDebt));
    }

    /**
        @notice returns BLOCKS valuation of asset
        @param _token address
        @param _amount uint
        @return value_ uint
     */
    function tokenValue(address _token, uint256 _amount) public view override returns (uint256 value_) {
        value_ = _amount.mul(10**IERC20Metadata(address(BLOCKS)).decimals()).div(10**IERC20Metadata(_token).decimals());

        if (permissions[STATUS.LIQUIDITYTOKEN][_token]) {
            value_ = IBondingCalculator(bondCalculator[_token]).valuation(_token, _amount);
        }
    }
}
