// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SimpleGateway.sol";

/**
 * @title SimpleAggregator
 * @dev A contract that processes orders from the SimpleGateway
 * by checking rates and determining whether to fulfill or refund.
 */
contract SimpleAggregator {
    // State variables
    SimpleGateway public gateway;
    uint256 public rateTolerance = 100; // In basis points (100 = 1%)
    
    // Events
    event OrderProcessed(uint256 orderId, uint256 expectedRate, uint256 currentRate, bool fulfilled);
    event ToleranceUpdated(uint256 newTolerance);
    
    // Constructor
    constructor(address _gateway) {
        require(_gateway != address(0), "Invalid gateway address");
        gateway = SimpleGateway(_gateway);
    }
    
    /**
     * @dev Sets the rate tolerance
     * @param _tolerance The new tolerance in basis points
     */
    function setRateTolerance(uint256 _tolerance) external {
        require(msg.sender == gateway.owner(), "Only gateway owner can call");
        require(_tolerance <= 1000, "Tolerance too high"); // Max 10%
        rateTolerance = _tolerance;
        emit ToleranceUpdated(_tolerance);
    }
    
    /**
     * @dev Processes an order by checking the current rate against the expected rate
     * @param _orderId The order ID
     * @param _currentRate The current exchange rate
     * @param _liquidityProvider The address of the liquidity provider
     */
    function processOrder(
        uint256 _orderId,
        uint256 _currentRate,
        address _liquidityProvider
    ) external {
        require(_liquidityProvider != address(0), "Invalid LP address");
        
        // Get order information from gateway
        (
            ,
            ,
            uint256 expectedRate,
            ,
            ,
            bool isFulfilled,
            bool isRefunded,
            
        ) = gateway.getOrderInfo(_orderId);
        
        require(!isFulfilled && !isRefunded, "Order already processed");
        
        // Calculate rate difference
        uint256 rateDiff;
        if (_currentRate > expectedRate) {
            rateDiff = ((_currentRate - expectedRate) * 10000) / expectedRate;
        } else {
            rateDiff = ((expectedRate - _currentRate) * 10000) / expectedRate;
        }
        
        // Check if rate is within tolerance
        if (rateDiff <= rateTolerance) {
            // Rate is acceptable, fulfill the order
            gateway.fulfillOrder(_orderId, _liquidityProvider);
            emit OrderProcessed(_orderId, expectedRate, _currentRate, true);
        } else {
            // Rate is outside tolerance, refund the order
            gateway.refundOrder(_orderId);
            emit OrderProcessed(_orderId, expectedRate, _currentRate, false);
        }
    }
}