// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts@4.9.3/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts@4.9.3/access/Ownable.sol";
import "@openzeppelin/contracts@4.9.3/security/ReentrancyGuard.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";


/**
 * @title SimpleGateway
 * @dev A contract that allows users to create crypto exchange orders
 * and processes them through an aggregator.
 */
contract SimpleGateway is Ownable, ReentrancyGuard {
    // State variables
    address public aggregator;
    address public treasury;
    uint256 public protocolFeePercent; // Fee in basis points (100 = 1%)
    uint256 public orderIdCounter;
    IUniswapV2Router02 public immutable uniswapRouter; // Router for performing token swaps
    address public immutable USDC; // USDC token contract address

    // Mapping to track supported tokens
    mapping(address => bool) public supportedTokens;
    
    // Order struct to store order information
    struct Order {
        address token;
        uint256 amount;
        uint256 rate;
        address creator;
        address refundAddress;
        bool isFulfilled;
        bool isRefunded;
        uint256 timestamp;
    }
    
    // Mapping to store orders by ID
    mapping(uint256 => Order) public orders;
    
    // Events
    event OrderCreated(uint256 orderId, address token, uint256 amount, uint256 rate, address refundAddress);
    event OrderFulfilled(uint256 orderId, address liquidityProvider);
    event OrderRefunded(uint256 orderId);
    event AggregatorSet(address aggregator);
    event TokenSupportUpdated(address token, bool isSupported);
    event TreasuryUpdated(address newTreasury);
    event ProtocolFeeUpdated(uint256 newFeePercent);
    event SwapAndCreateOrder(address inputToken, uint256 inputAmount, uint256 usdcReceived, uint256 orderId);
    
    // Constructor
    constructor(address _treasury, uint256 _protocolFeePercent, address _uniswapRouter, address _usdc) {
        require(_treasury != address(0), "Invalid treasury address");
        require(_protocolFeePercent <= 1000, "Fee too high"); // Max 10%
        require(_uniswapRouter != address(0), "Invalid router address");
        require(_usdc != address(0), "Invalid USDC address");
        
        treasury = _treasury;
        protocolFeePercent = _protocolFeePercent;
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
        USDC = _usdc;
    }
    
    // Modifier to ensure only the aggregator can call certain functions
    modifier onlyAggregator() {
        require(msg.sender == aggregator, "Only aggregator can call");
        _;
    }
    
    /**
     * @dev Sets the aggregator address
     * @param _aggregator The address of the aggregator contract
     */
    function setAggregator(address _aggregator) external onlyOwner {
        require(_aggregator != address(0), "Invalid aggregator address");
        aggregator = _aggregator;
        emit AggregatorSet(_aggregator);
    }
    
    /**
     * @dev Sets token support status
     * @param _token The token address
     * @param _isSupported Whether the token is supported
     */
    function setTokenSupport(address _token, bool _isSupported) external onlyOwner {
        require(_token != address(0), "Invalid token address");
        supportedTokens[_token] = _isSupported;
        emit TokenSupportUpdated(_token, _isSupported);
    }
    
    /**
     * @dev Updates the treasury address
     * @param _treasury The new treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury address");
        treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }
    
    /**
     * @dev Updates the protocol fee percentage
     * @param _protocolFeePercent The new fee percentage in basis points
     */
    function setProtocolFeePercent(uint256 _protocolFeePercent) external onlyOwner {
        require(_protocolFeePercent <= 1000, "Fee too high"); // Max 10%
        protocolFeePercent = _protocolFeePercent;
        emit ProtocolFeeUpdated(_protocolFeePercent);
    }
    
    /**
     * @dev Creates a new exchange order
     * @param _token The token address
     * @param _amount The amount of tokens
     * @param _rate The expected exchange rate
     * @param _refundAddress The address to refund tokens if needed
     * @return orderId The ID of the created order
     */
    function createOrder(
        address _token,
        uint256 _amount,
        uint256 _rate,
        address _refundAddress
    ) external nonReentrant returns (uint256 orderId) {
        require(supportedTokens[_token], "Token not supported");
        require(_amount > 0, "Amount must be greater than 0");
        require(_rate > 0, "Rate must be greater than 0");
        require(_refundAddress != address(0), "Invalid refund address");
        
        // Transfer tokens from user to contract
        IERC20 token = IERC20(_token);
        require(token.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        
        // Create order
        orderId = orderIdCounter++;
        orders[orderId] = Order({
            token: _token,
            amount: _amount,
            rate: _rate,
            creator: msg.sender,
            refundAddress: _refundAddress,
            isFulfilled: false,
            isRefunded: false,
            timestamp: block.timestamp
        });
        
        emit OrderCreated(orderId, _token, _amount, _rate, _refundAddress);
    }
    
    /**
     * @dev Swaps any token to USDC and then creates an order
     * @param _inputToken The token to swap from
     * @param _inputAmount The amount of input tokens
     * @param _minUsdcAmount The minimum USDC amount expected after swap
     * @param _rate The expected exchange rate for the order
     * @param _refundAddress The address to refund tokens if needed
     * @param _deadline The deadline for the swap transaction
     * @return orderId The ID of the created order
     */
    function swapAndCreateOrder(
        address _inputToken,
        uint256 _inputAmount,
        uint256 _minUsdcAmount,
        uint256 _rate,
        address _refundAddress,
        uint256 _deadline
    ) external nonReentrant returns (uint256 orderId) {
        require(_inputToken != address(0), "Invalid input token");
        require(_inputAmount > 0, "Input amount must be greater than 0");
        require(_minUsdcAmount > 0, "Min USDC amount must be greater than 0");
        require(_rate > 0, "Rate must be greater than 0");
        require(_refundAddress != address(0), "Invalid refund address");
        require(supportedTokens[USDC], "USDC not supported");
        
        // Transfer input tokens from user to this contract
        IERC20 inputToken = IERC20(_inputToken);
        require(inputToken.transferFrom(msg.sender, address(this), _inputAmount), "Transfer failed");
        
        // Approve router to spend tokens
        inputToken.approve(address(uniswapRouter), _inputAmount);
        
        // Create swap path
        address[] memory path = new address[](2);
        path[0] = _inputToken;
        path[1] = USDC;
        
        // Execute the swap
        uint256[] memory amounts = uniswapRouter.swapExactTokensForTokens(
            _inputAmount,
            _minUsdcAmount,
            path,
            address(this),
            _deadline
        );
        
        uint256 usdcReceived = amounts[amounts.length - 1];
        
        // Create order with the USDC received
        orderId = orderIdCounter++;
        orders[orderId] = Order({
            token: USDC,
            amount: usdcReceived,
            rate: _rate,
            creator: msg.sender,
            refundAddress: _refundAddress,
            isFulfilled: false,
            isRefunded: false,
            timestamp: block.timestamp
        });
        
        emit SwapAndCreateOrder(_inputToken, _inputAmount, usdcReceived, orderId);
        emit OrderCreated(orderId, USDC, usdcReceived, _rate, _refundAddress);
    }
    
    /**
     * @dev Fulfills an order (called by the aggregator)
     * @param _orderId The order ID
     * @param _liquidityProvider The address of the liquidity provider
     */
    function fulfillOrder(uint256 _orderId, address _liquidityProvider) external onlyAggregator nonReentrant {
        Order storage order = orders[_orderId];
        require(!order.isFulfilled && !order.isRefunded, "Order already processed");
        
        order.isFulfilled = true;
        
        // Calculate protocol fee
        uint256 feeAmount = (order.amount * protocolFeePercent) / 10000;
        uint256 netAmount = order.amount - feeAmount;
        
        // Transfer tokens to liquidity provider and fee to treasury
        IERC20 token = IERC20(order.token);
        require(token.transfer(_liquidityProvider, netAmount), "LP transfer failed");
        require(token.transfer(treasury, feeAmount), "Fee transfer failed");
        
        emit OrderFulfilled(_orderId, _liquidityProvider);
    }
    
    /**
     * @dev Refunds an order (called by the aggregator)
     * @param _orderId The order ID
     */
    function refundOrder(uint256 _orderId) external onlyAggregator nonReentrant {
        Order storage order = orders[_orderId];
        require(!order.isFulfilled && !order.isRefunded, "Order already processed");
        
        order.isRefunded = true;
        
        // Transfer tokens back to refund address
        IERC20 token = IERC20(order.token);
        require(token.transfer(order.refundAddress, order.amount), "Refund transfer failed");
        
        emit OrderRefunded(_orderId);
    }
    
    /**
     * @dev Gets information about an order
     * @param _orderId The order ID
     * @return token         The token address for this order
     * @return amount        The amount of tokens in the order
     * @return rate          The expected exchange rate
     * @return creator       The address that created the order
     * @return refundAddress The address to refund if the order is cancelled
     * @return isFulfilled   Whether the order has been fulfilled
     * @return isRefunded    Whether the order has been refunded
     * @return timestamp     The block timestamp when the order was created
     */
    function getOrderInfo(uint256 _orderId) external view returns (
        address token,
        uint256 amount,
        uint256 rate,
        address creator,
        address refundAddress,
        bool isFulfilled,
        bool isRefunded,
        uint256 timestamp
    ) {
        Order storage order = orders[_orderId];
        return (
            order.token,
            order.amount,
            order.rate,
            order.creator,
            order.refundAddress,
            order.isFulfilled,
            order.isRefunded,
            order.timestamp
        );
    }
}
