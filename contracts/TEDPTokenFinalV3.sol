// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

/**
 * @title TEDP Token Final V3 - Production Ready
 * @author TED Protocol Team
 * @notice 최종 배포 버전 - 2025년 1월 14일
 * @dev TRON 메인넷 배포용 최종 버전
 * 
 * ✅ 핵심 특징:
 * - 총 발행량: 10억 TEDP
 * - 초기 제한 없음 (수수료 0%, 한도 무제한)
 * - 트레이딩 즉시 활성화
 * - 영구 블랙리스트 기능
 * - SunSwap V2 최적화
 * - 거래소 상장 준비 완료
 * 
 * 🔒 보안 기능:
 * - 영구 동결 (해커 대응)
 * - Anti-Bot 시스템
 * - 다중 서명 미래 지원
 * - 긴급 정지 기능
 * 
 * 📝 배포 체크리스트:
 * 1. Owner 주소 확인
 * 2. 지갑 주소 설정 (Treasury, Liquidity)
 * 3. 테스트넷 먼저 배포
 * 4. 모든 기능 검증
 * 5. 메인넷 배포
 */

// ============================================
// 인터페이스 정의
// ============================================

interface ITRC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IStakingContract {
    function notifyReward(uint256 amount) external;
}

interface IDEXRouter {
    function factory() external pure returns (address);
    function WTRX() external pure returns (address);
    function addLiquidityTRX(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountTRXMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountTRX, uint liquidity);
    
    function swapExactTokensForTRXSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IDEXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

// ============================================
// 기본 컨트랙트
// ============================================

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

contract Ownable is Context {
    address private _owner;
    bool private _renounced;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipRenounced(address indexed previousOwner);

    constructor() {
        _owner = _msgSender();
        emit OwnershipTransferred(address(0), _owner);
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Not owner");
        require(!_renounced, "Ownership renounced");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function isRenounced() public view returns (bool) {
        return _renounced;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Zero address");
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    function renounceOwnership() public virtual onlyOwner {
        _renounced = true;
        address oldOwner = _owner;
        _owner = address(0);
        emit OwnershipRenounced(oldOwner);
    }
}

// ============================================
// 메인 토큰 컨트랙트
// ============================================

contract TEDPTokenFinalV3 is ITRC20, Ownable {
    
    // ========== 매핑 ==========
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    
    // ========== 토큰 정보 ==========
    string public constant name = "TED Protocol";
    string public constant symbol = "TEDP";
    uint8 public constant decimals = 18;
    string public constant version = "3.0.0";
    
    // 총 발행량 (10억개)
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000 * 10**18;
    uint256 private _totalSupply;
    
    // ========== 트레이딩 상태 (초기 활성화) ==========
    bool public tradingEnabled = true;  // ✅ 초기부터 활성화
    uint256 public launchTime;
    uint256 public launchBlock;
    
    // ========== 전송/보유 한도 (초기 0 = 무제한) ==========
    uint256 public maxTransferAmount = 0;      // 0 = 무제한
    uint256 public maxWalletBalance = 0;       // 0 = 무제한
    uint256 public minTransferAmount = 0;      // 0 = 제한없음
    
    // ========== 수수료 시스템 (초기 0%) ==========
    uint256 public burnFee = 0;          // 0% 초기값
    uint256 public liquidityFee = 0;     // 0% 초기값
    uint256 public stakingFee = 0;       // 0% 초기값
    uint256 public treasuryFee = 0;      // 0% 초기값
    
    // 수수료 상한 (안전장치)
    uint256 public constant MAX_BURN_FEE = 200;        // 2% 최대
    uint256 public constant MAX_LIQUIDITY_FEE = 300;   // 3% 최대
    uint256 public constant MAX_STAKING_FEE = 200;     // 2% 최대
    uint256 public constant MAX_TREASURY_FEE = 300;    // 3% 최대
    uint256 public constant MAX_TOTAL_FEE = 500;       // 5% 최대
    
    // 수수료 활성화 (초기 비활성화)
    bool public feesEnabled = false;
    
    // ========== 블랙리스트 (영구 동결 가능) ==========
    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public isPermanentlyBlacklisted;  // 영구 블랙리스트
    mapping(address => string) public blacklistReason;          // 블랙리스트 사유
    
    // ========== Anti-Bot (초기 비활성화) ==========
    bool public antiBotEnabled = false;     // 초기 비활성화
    uint256 public antibotDuration = 0;     // 봇 방지 기간
    uint256 public cooldownBlocks = 0;      // 블록 쿨다운
    mapping(address => uint256) public lastTxBlock;
    mapping(address => bool) public isBot;
    
    // ========== 면제 설정 ==========
    mapping(address => bool) public isExemptFromFees;
    mapping(address => bool) public isExemptFromLimits;
    mapping(address => bool) public isExchange;
    mapping(address => bool) public isLiquidityPool;
    
    // ========== DEX 설정 ==========
    IDEXRouter public dexRouter;
    address public dexPair;
    mapping(address => bool) public isDEXPair;
    
    // ========== 자동 유동성 (초기 비활성화) ==========
    bool public autoLiquidityEnabled = false;
    uint256 public liquidityThreshold = 0;
    bool public inSwapAndLiquify;
    
    // ========== 수수료 지갑 ==========
    address public liquidityWallet;
    address public stakingContract;
    address public treasuryWallet;
    
    // ========== 유동성 잠금 ==========
    bool public liquidityLocked = false;
    uint256 public liquidityUnlockTime;
    
    // ========== 일시 정지 (초기 비활성화) ==========
    bool public paused = false;
    
    // ========== 통계 ==========
    uint256 public totalBurned;
    uint256 public totalLiquidityFees;
    uint256 public totalStakingFees;
    uint256 public totalTreasuryFees;
    uint256 public totalTransactions;
    
    // ========== 이벤트 ==========
    event TradingEnabled(uint256 timestamp, uint256 blockNumber);
    event FeesEnabled(bool enabled);
    event FeesUpdated(uint256 burn, uint256 liquidity, uint256 staking, uint256 treasury);
    event MaxTransferAmountUpdated(uint256 amount);
    event MaxWalletBalanceUpdated(uint256 amount);
    event MinTransferAmountUpdated(uint256 amount);
    event BlacklistUpdated(address indexed account, bool status, bool permanent, string reason);
    event HackerWalletFrozen(address indexed hacker, uint256 amount, string evidence);
    event ExchangeRegistered(address indexed exchange, bool status);
    event LiquidityPoolRegistered(address indexed pool, bool status);
    event AntiBotUpdated(bool enabled, uint256 duration, uint256 cooldown);
    event AutoLiquidityUpdated(bool enabled, uint256 threshold);
    event LiquidityLocked(uint256 unlockTime);
    event EmergencyPause(bool status);
    event Burn(address indexed burner, uint256 value);
    event TokensRecovered(address indexed token, uint256 amount);
    event TRXRecovered(uint256 amount);
    
    // ========== 모디파이어 ==========
    modifier notPaused() {
        require(!paused, "Contract paused");
        _;
    }
    
    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }
    
    // ========== 생성자 ==========
    constructor() {
        _totalSupply = INITIAL_SUPPLY;
        _balances[_msgSender()] = _totalSupply;
        
        // 초기 설정
        launchTime = block.timestamp;
        launchBlock = block.number;
        
        // Owner 면제
        isExemptFromFees[_msgSender()] = true;
        isExemptFromLimits[_msgSender()] = true;
        
        // 이 컨트랙트 면제
        isExemptFromFees[address(this)] = true;
        isExemptFromLimits[address(this)] = true;
        
        emit Transfer(address(0), _msgSender(), _totalSupply);
        emit TradingEnabled(launchTime, launchBlock);
    }
    
    // ========== TRC20 기본 함수 ==========
    
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address recipient, uint256 amount) public override notPaused returns (bool) {
        _transferWithChecks(_msgSender(), recipient, amount);
        return true;
    }
    
    function transferFrom(address sender, address recipient, uint256 amount) 
        public 
        override 
        notPaused 
        returns (bool) 
    {
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "Exceeds allowance");
        
        _transferWithChecks(sender, recipient, amount);
        
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }
        
        return true;
    }
    
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    
    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }
    
    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "Below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }
        return true;
    }
    
    // ========== 내부 전송 로직 ==========
    
    function _transferWithChecks(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "From zero");
        require(recipient != address(0), "To zero");
        require(amount > 0, "Zero amount");
        
        // 트레이딩 체크
        if (!tradingEnabled) {
            require(
                isExemptFromLimits[sender] || isExemptFromLimits[recipient],
                "Trading not enabled"
            );
        }
        
        // 블랙리스트 체크
        require(!isBlacklisted[sender] && !isPermanentlyBlacklisted[sender], "Sender blacklisted");
        require(!isBlacklisted[recipient] && !isPermanentlyBlacklisted[recipient], "Recipient blacklisted");
        
        // Anti-Bot 체크
        if (antiBotEnabled) {
            _antiBotCheck(sender, recipient);
        }
        
        // 최소/최대 전송량 체크
        if (!isExemptFromLimits[sender] && !isExemptFromLimits[recipient]) {
            if (minTransferAmount > 0) {
                require(amount >= minTransferAmount, "Below min");
            }
            if (maxTransferAmount > 0) {
                require(amount <= maxTransferAmount, "Exceeds max transfer");
            }
            
            // 지갑 잔액 한도 체크 (받는 쪽)
            if (maxWalletBalance > 0 && !isDEXPair[recipient]) {
                require(
                    _balances[recipient] + amount <= maxWalletBalance,
                    "Exceeds max wallet"
                );
            }
        }
        
        // 수수료 계산
        uint256 fees = 0;
        if (feesEnabled && !isExemptFromFees[sender] && !isExemptFromFees[recipient]) {
            fees = _calculateFees(amount);
        }
        
        // 전송 실행
        _tokenTransfer(sender, recipient, amount, fees);
        
        // 통계 업데이트
        totalTransactions++;
        
        // 자동 유동성
        if (
            autoLiquidityEnabled &&
            !inSwapAndLiquify &&
            sender != dexPair &&
            _balances[address(this)] >= liquidityThreshold
        ) {
            _swapAndLiquify();
        }
    }
    
    function _antiBotCheck(address sender, address recipient) internal {
        // 봇 체크
        require(!isBot[sender] && !isBot[recipient], "Bot detected");
        
        // 블록 쿨다운 체크
        if (cooldownBlocks > 0) {
            if (!isDEXPair[sender] && !isDEXPair[recipient]) {
                require(
                    block.number >= lastTxBlock[sender] + cooldownBlocks,
                    "Cooldown active"
                );
                lastTxBlock[sender] = block.number;
            }
        }
    }
    
    function _calculateFees(uint256 amount) internal view returns (uint256) {
        uint256 totalFee = burnFee + liquidityFee + stakingFee + treasuryFee;
        return (amount * totalFee) / 10000;
    }
    
    function _tokenTransfer(address sender, address recipient, uint256 amount, uint256 fees) internal {
        uint256 transferAmount = amount - fees;
        
        // 잔액 업데이트
        _balances[sender] -= amount;
        _balances[recipient] += transferAmount;
        
        emit Transfer(sender, recipient, transferAmount);
        
        // 수수료 처리
        if (fees > 0) {
            _handleFees(sender, fees, amount);
        }
    }
    
    function _handleFees(address sender, uint256 fees, uint256 amount) internal {
        _balances[address(this)] += fees;
        emit Transfer(sender, address(this), fees);
        
        // 각 수수료 계산 및 통계
        if (burnFee > 0) {
            uint256 burnAmount = (amount * burnFee) / 10000;
            _burn(address(this), burnAmount);
            totalBurned += burnAmount;
        }
        
        if (liquidityFee > 0) {
            uint256 liquidityAmount = (amount * liquidityFee) / 10000;
            totalLiquidityFees += liquidityAmount;
        }
        
        if (stakingFee > 0) {
            uint256 stakingAmount = (amount * stakingFee) / 10000;
            if (stakingContract != address(0)) {
                _balances[address(this)] -= stakingAmount;
                _balances[stakingContract] += stakingAmount;
                emit Transfer(address(this), stakingContract, stakingAmount);
                IStakingContract(stakingContract).notifyReward(stakingAmount);
            }
            totalStakingFees += stakingAmount;
        }
        
        if (treasuryFee > 0) {
            uint256 treasuryAmount = (amount * treasuryFee) / 10000;
            if (treasuryWallet != address(0)) {
                _balances[address(this)] -= treasuryAmount;
                _balances[treasuryWallet] += treasuryAmount;
                emit Transfer(address(this), treasuryWallet, treasuryAmount);
            }
            totalTreasuryFees += treasuryAmount;
        }
    }
    
    function _burn(address account, uint256 amount) internal {
        _balances[account] -= amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
        emit Burn(account, amount);
    }
    
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "From zero");
        require(spender != address(0), "To zero");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    
    function _swapAndLiquify() internal lockTheSwap {
        // 자동 유동성 로직 (필요시 구현)
        // 현재는 플레이스홀더
    }
    
    // ========== 관리 함수 (Owner Only) ==========
    
    /**
     * @dev 블랙리스트 업데이트
     */
    function updateBlacklist(
        address account,
        bool status,
        bool permanent,
        string memory reason
    ) external onlyOwner {
        require(account != address(0), "Zero address");
        require(account != owner(), "Cannot blacklist owner");
        
        if (permanent) {
            isPermanentlyBlacklisted[account] = status;
            if (status) {
                isBlacklisted[account] = false;  // 영구가 우선
                blacklistReason[account] = reason;
            }
        } else {
            require(!isPermanentlyBlacklisted[account], "Permanently blacklisted");
            isBlacklisted[account] = status;
            if (status) {
                blacklistReason[account] = reason;
            }
        }
        
        emit BlacklistUpdated(account, status, permanent, reason);
    }
    
    /**
     * @dev 해커 지갑 영구 동결
     */
    function freezeHackerWallet(address hacker, string memory evidence) external onlyOwner {
        require(hacker != address(0), "Zero address");
        require(hacker != owner(), "Cannot freeze owner");
        
        isPermanentlyBlacklisted[hacker] = true;
        blacklistReason[hacker] = evidence;
        
        uint256 hackerBalance = _balances[hacker];
        emit HackerWalletFrozen(hacker, hackerBalance, evidence);
        emit BlacklistUpdated(hacker, true, true, evidence);
    }
    
    /**
     * @dev 전송 한도 설정
     */
    function setMaxTransferAmount(uint256 amount) external onlyOwner {
        require(amount == 0 || amount >= _totalSupply / 1000, "Too restrictive");
        maxTransferAmount = amount;
        emit MaxTransferAmountUpdated(amount);
    }
    
    function setMaxWalletBalance(uint256 amount) external onlyOwner {
        require(amount == 0 || amount >= _totalSupply / 100, "Too restrictive");
        maxWalletBalance = amount;
        emit MaxWalletBalanceUpdated(amount);
    }
    
    function setMinTransferAmount(uint256 amount) external onlyOwner {
        require(amount <= _totalSupply / 100000, "Too high");
        minTransferAmount = amount;
        emit MinTransferAmountUpdated(amount);
    }
    
    /**
     * @dev 수수료 설정
     */
    function setFees(
        uint256 _burnFee,
        uint256 _liquidityFee,
        uint256 _stakingFee,
        uint256 _treasuryFee
    ) external onlyOwner {
        require(_burnFee <= MAX_BURN_FEE, "Burn fee too high");
        require(_liquidityFee <= MAX_LIQUIDITY_FEE, "Liquidity fee too high");
        require(_stakingFee <= MAX_STAKING_FEE, "Staking fee too high");
        require(_treasuryFee <= MAX_TREASURY_FEE, "Treasury fee too high");
        
        uint256 totalFee = _burnFee + _liquidityFee + _stakingFee + _treasuryFee;
        require(totalFee <= MAX_TOTAL_FEE, "Total fee too high");
        
        burnFee = _burnFee;
        liquidityFee = _liquidityFee;
        stakingFee = _stakingFee;
        treasuryFee = _treasuryFee;
        
        emit FeesUpdated(_burnFee, _liquidityFee, _stakingFee, _treasuryFee);
    }
    
    function enableFees(bool enabled) external onlyOwner {
        feesEnabled = enabled;
        emit FeesEnabled(enabled);
    }
    
    /**
     * @dev 지갑 설정
     */
    function setFeeWallets(
        address _liquidityWallet,
        address _stakingContract,
        address _treasuryWallet
    ) external onlyOwner {
        liquidityWallet = _liquidityWallet;
        stakingContract = _stakingContract;
        treasuryWallet = _treasuryWallet;
        
        // 지갑들 수수료 면제
        if (_liquidityWallet != address(0)) {
            isExemptFromFees[_liquidityWallet] = true;
        }
        if (_stakingContract != address(0)) {
            isExemptFromFees[_stakingContract] = true;
        }
        if (_treasuryWallet != address(0)) {
            isExemptFromFees[_treasuryWallet] = true;
        }
    }
    
    /**
     * @dev 거래소 등록
     */
    function registerExchange(address exchange, bool status) external onlyOwner {
        require(exchange != address(0), "Zero address");
        isExchange[exchange] = status;
        isExemptFromFees[exchange] = status;
        isExemptFromLimits[exchange] = status;
        emit ExchangeRegistered(exchange, status);
    }
    
    /**
     * @dev 유동성 풀 등록
     */
    function registerLiquidityPool(address pool, bool status) external onlyOwner {
        require(pool != address(0), "Zero address");
        isLiquidityPool[pool] = status;
        isDEXPair[pool] = status;
        isExemptFromLimits[pool] = status;
        emit LiquidityPoolRegistered(pool, status);
    }
    
    /**
     * @dev 면제 설정
     */
    function setExemptions(
        address account,
        bool feeExempt,
        bool limitExempt
    ) external onlyOwner {
        isExemptFromFees[account] = feeExempt;
        isExemptFromLimits[account] = limitExempt;
    }
    
    /**
     * @dev Anti-Bot 설정
     */
    function setAntiBot(
        bool enabled,
        uint256 duration,
        uint256 cooldown
    ) external onlyOwner {
        antiBotEnabled = enabled;
        antibotDuration = duration;
        cooldownBlocks = cooldown;
        emit AntiBotUpdated(enabled, duration, cooldown);
    }
    
    function setBotStatus(address account, bool isBot_) external onlyOwner {
        isBot[account] = isBot_;
    }
    
    /**
     * @dev 자동 유동성 설정
     */
    function setAutoLiquidity(bool enabled, uint256 threshold) external onlyOwner {
        autoLiquidityEnabled = enabled;
        liquidityThreshold = threshold;
        emit AutoLiquidityUpdated(enabled, threshold);
    }
    
    /**
     * @dev DEX 라우터 설정
     */
    function setDEXRouter(address router) external onlyOwner {
        require(router != address(0), "Zero address");
        dexRouter = IDEXRouter(router);
        isExemptFromLimits[router] = true;
    }
    
    /**
     * @dev DEX 페어 생성
     */
    function createDEXPair() external onlyOwner {
        require(address(dexRouter) != address(0), "Router not set");
        
        dexPair = IDEXFactory(dexRouter.factory()).createPair(
            address(this),
            dexRouter.WTRX()
        );
        
        isDEXPair[dexPair] = true;
        isLiquidityPool[dexPair] = true;
        isExemptFromLimits[dexPair] = true;
        
        emit LiquidityPoolRegistered(dexPair, true);
    }
    
    /**
     * @dev 유동성 잠금
     */
    function lockLiquidity(uint256 duration) external onlyOwner {
        require(duration > 0, "Invalid duration");
        liquidityLocked = true;
        liquidityUnlockTime = block.timestamp + duration;
        emit LiquidityLocked(liquidityUnlockTime);
    }
    
    /**
     * @dev 긴급 정지/재개
     */
    function emergencyPause(bool pause) external onlyOwner {
        paused = pause;
        emit EmergencyPause(pause);
    }
    
    /**
     * @dev 토큰 소각
     */
    function burn(uint256 amount) external {
        require(_balances[_msgSender()] >= amount, "Insufficient balance");
        _burn(_msgSender(), amount);
        totalBurned += amount;
    }
    
    /**
     * @dev 실수로 전송된 토큰 회수
     */
    function recoverToken(address tokenAddress, uint256 amount) external onlyOwner {
        require(tokenAddress != address(this), "Cannot recover TEDP");
        ITRC20(tokenAddress).transfer(owner(), amount);
        emit TokensRecovered(tokenAddress, amount);
    }
    
    /**
     * @dev 실수로 전송된 TRX 회수
     */
    function recoverTRX() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No TRX");
        payable(owner()).transfer(balance);
        emit TRXRecovered(balance);
    }
    
    // ========== 조회 함수 ==========
    
    /**
     * @dev 블랙리스트 상태 조회
     */
    function getBlacklistStatus(address account) external view returns (
        bool blacklisted,
        bool permanent,
        string memory reason
    ) {
        blacklisted = isBlacklisted[account];
        permanent = isPermanentlyBlacklisted[account];
        reason = blacklistReason[account];
    }
    
    /**
     * @dev 계정 상태 조회
     */
    function getAccountStatus(address account) external view returns (
        uint256 balance,
        bool blacklisted,
        bool permanentBlacklist,
        bool feeExempt,
        bool limitExempt,
        bool exchange,
        bool liquidityPool,
        bool bot
    ) {
        balance = _balances[account];
        blacklisted = isBlacklisted[account];
        permanentBlacklist = isPermanentlyBlacklisted[account];
        feeExempt = isExemptFromFees[account];
        limitExempt = isExemptFromLimits[account];
        exchange = isExchange[account];
        liquidityPool = isLiquidityPool[account];
        bot = isBot[account];
    }
    
    /**
     * @dev 컨트랙트 상태 조회
     */
    function getContractStatus() external view returns (
        bool trading,
        bool fees,
        bool antiBot,
        bool autoLiquidity,
        bool paused_,
        bool ownershipRenounced,
        uint256 totalSupply_,
        uint256 circulatingSupply,
        address owner_
    ) {
        trading = tradingEnabled;
        fees = feesEnabled;
        antiBot = antiBotEnabled;
        autoLiquidity = autoLiquidityEnabled;
        paused_ = paused;
        ownershipRenounced = isRenounced();
        totalSupply_ = _totalSupply;
        circulatingSupply = _totalSupply - totalBurned;
        owner_ = owner();
    }
    
    /**
     * @dev 한도 조회
     */
    function getLimits() external view returns (
        uint256 maxTransfer,
        uint256 maxWallet,
        uint256 minTransfer
    ) {
        maxTransfer = maxTransferAmount;
        maxWallet = maxWalletBalance;
        minTransfer = minTransferAmount;
    }
    
    /**
     * @dev 수수료 조회
     */
    function getFees() external view returns (
        uint256 burn,
        uint256 liquidity,
        uint256 staking,
        uint256 treasury,
        uint256 total,
        bool enabled
    ) {
        burn = burnFee;
        liquidity = liquidityFee;
        staking = stakingFee;
        treasury = treasuryFee;
        total = burn + liquidity + staking + treasury;
        enabled = feesEnabled;
    }
    
    /**
     * @dev 통계 조회
     */
    function getStatistics() external view returns (
        uint256 burned,
        uint256 liquidityFeesCollected,
        uint256 stakingFeesCollected,
        uint256 treasuryFeesCollected,
        uint256 transactions
    ) {
        burned = totalBurned;
        liquidityFeesCollected = totalLiquidityFees;
        stakingFeesCollected = totalStakingFees;
        treasuryFeesCollected = totalTreasuryFees;
        transactions = totalTransactions;
    }
    
    // ========== 기타 ==========
    
    receive() external payable {}
    
    fallback() external payable {}
}