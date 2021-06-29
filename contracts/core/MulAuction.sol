// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MulAuction is Ownable {
    IERC721 public GPToken;
    IERC20 public MulToken;
    using SafeMath for uint;
    using SafeERC20 for IERC20;
    
    struct Pool {
        bool end;
        uint closeTime;
        uint maxTime;
        uint plusTime;
        uint addPrice;
        uint tokenId;
        address bidder;
        uint currentPrice;
    }
    
    event Create(uint pid, uint tokenId, uint base, uint add, uint plusTime, uint maxTime);
    event Bid(uint pid, address indexed bidder, uint bidPrice);
    event Claim(uint pid, uint dealPrice, address indexed bidder);
    event Stop(uint pid);
    
    uint public cntOfPool;
    Pool[] public pools;
    
    constructor(IERC721 _GPToken, IERC20 _MulToken) {
    	require(address(_GPToken) != address(0), "INVALID_ADDRESS");
		require(address(_MulToken) != address(0), "INVALID_ADDRESS");
        GPToken = _GPToken;
        MulToken = _MulToken;
    }

    modifier validatePoolByPid(uint _pid) {
    	require(_pid < cntOfPool, "Pool does not exist");
    	_;
    }
    
    function create(uint startTime, uint maxTime, uint plusTime, uint basePrice, uint addPrice, uint tokenId) external onlyOwner {
        GPToken.safeTransferFrom(msg.sender, address(this), tokenId);
        Pool memory pool = Pool({
            end: false,
            closeTime: startTime.add(maxTime),
            plusTime: plusTime,
            maxTime: maxTime,
            addPrice: addPrice,
            tokenId: tokenId,
            bidder: address(0),
            currentPrice: basePrice
        });
        
        pools.push(pool);
        cntOfPool++;
        emit Create(cntOfPool, tokenId, basePrice, addPrice, plusTime, maxTime);
    }
    
    function min(uint a, uint b) internal pure returns(uint){
        return a < b ? a: b;
    }
    
    function bid(uint pid, uint bidPrice) external validatePoolByPid(pid) {
        Pool storage pool = pools[pid];
        require(!pool.end, "Pool End");
        require(block.number < pool.closeTime, "Cannot Bid Now");
        require(bidPrice >= pool.currentPrice.add(pool.addPrice));
        
        MulToken.safeTransferFrom(msg.sender, address(this), bidPrice);
        if(pool.bidder != address(0)) {
            MulToken.safeTransfer(pool.bidder, pool.currentPrice);
        }
        
        pool.currentPrice = bidPrice;
        pool.closeTime = min(pool.closeTime.add(pool.plusTime), block.number.add(pool.maxTime));
        pool.bidder = msg.sender;
        
        emit Bid(pid, msg.sender, bidPrice);
    }
    
    function claim(uint pid) external validatePoolByPid(pid) {
        Pool storage pool = pools[pid];
        require(!pool.end, "Pool End");
        require(block.number >= pool.closeTime, "Not Close Now");
        
        pool.end = true;
        if(pool.bidder != address(0)) {
            GPToken.safeTransferFrom(address(this), pool.bidder, pool.tokenId);
            MulToken.safeTransfer(owner(), pool.currentPrice);
        }
        
        emit Claim(pid, pool.currentPrice, pool.bidder);
    }
    
    function stop(uint pid) external onlyOwner validatePoolByPid(pid){
        Pool storage pool = pools[pid];
        require(!pool.end, "Pool End");
        
        pool.end = true;
        GPToken.safeTransferFrom(address(this), owner(), pool.tokenId);
        if(pool.bidder != address(0)) {
            MulToken.safeTransfer(pool.bidder, pool.currentPrice);
        }
        
        emit Stop(pid);
    }
}