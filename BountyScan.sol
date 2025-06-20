// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract BountyScan {
    struct Bounty {
        address creator;
        address targetAddress;
        uint256 amount;
        uint256 createdAt;
        bool claimed;
        address claimedBy;
        uint256 killmailId;
    }
    
    // State variables
    mapping(uint256 => Bounty) public bounties;
    mapping(address => uint256[]) public bountiesOnTarget;
    mapping(uint256 => uint256) public killmailToBounty;
    uint256 public bountyCounter;
    address public owner;
    
    // Events
    event BountyCreated(uint256 indexed bountyId, address indexed target, address indexed creator, uint256 amount);
    event BountyClaimed(uint256 indexed bountyId, address indexed killer, uint256 killmailId);
    event BountyCancelled(uint256 indexed bountyId);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    // Create a new bounty on a target
    function createBounty(address _targetAddress) external payable {
        require(msg.value > 0, "Bounty amount must be greater than 0");
        require(_targetAddress != address(0), "Invalid target address");
        require(_targetAddress != msg.sender, "Cannot place bounty on yourself");
        
        uint256 bountyId = bountyCounter++;
        
        bounties[bountyId] = Bounty({
            creator: msg.sender,
            targetAddress: _targetAddress,
            amount: msg.value,
            createdAt: block.timestamp,
            claimed: false,
            claimedBy: address(0),
            killmailId: 0
        });
        
        bountiesOnTarget[_targetAddress].push(bountyId);
        
        emit BountyCreated(bountyId, _targetAddress, msg.sender, msg.value);
    }
    
    // Claim a bounty with killmail proof (simplified - trusts caller for now)
    function claimBounty(
        uint256 _bountyId,
        uint256 _killmailId,
        address _killerAddress,
        address _victimAddress,
        uint256 _killTimestamp
    ) external {
        Bounty storage bounty = bounties[_bountyId];
        
        // Validations
        require(!bounty.claimed, "Bounty already claimed");
        require(bounty.amount > 0, "Bounty does not exist");
        require(_victimAddress == bounty.targetAddress, "Victim does not match bounty target");
        require(_killerAddress == msg.sender, "Only the killer can claim the bounty");
        require(_killTimestamp > bounty.createdAt, "Kill must be after bounty creation");
        require(killmailToBounty[_killmailId] == 0, "Killmail already used for another bounty");
        
        // Mark as claimed
        bounty.claimed = true;
        bounty.claimedBy = msg.sender;
        bounty.killmailId = _killmailId;
        killmailToBounty[_killmailId] = _bountyId;
        
        // Transfer the bounty amount to the killer
        (bool success, ) = payable(msg.sender).call{value: bounty.amount}("");
        require(success, "Transfer failed");
        
        emit BountyClaimed(_bountyId, msg.sender, _killmailId);
    }
    
    // Cancel an unclaimed bounty (only by creator)
    function cancelBounty(uint256 _bountyId) external {
        Bounty storage bounty = bounties[_bountyId];
        
        require(bounty.creator == msg.sender, "Only creator can cancel bounty");
        require(!bounty.claimed, "Cannot cancel claimed bounty");
        require(bounty.amount > 0, "Bounty does not exist");
        
        uint256 refundAmount = bounty.amount;
        bounty.amount = 0;
        bounty.claimed = true; // Prevent re-entrancy
        
        (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
        require(success, "Refund failed");
        
        emit BountyCancelled(_bountyId);
    }
    
    // Get all bounty IDs for a target
    function getBountiesOnTarget(address _target) external view returns (uint256[] memory) {
        return bountiesOnTarget[_target];
    }
    
    // Get active (unclaimed) bounties for a target
    function getActiveBountiesOnTarget(address _target) external view returns (uint256[] memory) {
        uint256[] memory allBounties = bountiesOnTarget[_target];
        uint256 activeCount = 0;
        
        // Count active bounties
        for (uint256 i = 0; i < allBounties.length; i++) {
            if (!bounties[allBounties[i]].claimed) {
                activeCount++;
            }
        }
        
        // Create array of active bounties
        uint256[] memory activeBounties = new uint256[](activeCount);
        uint256 currentIndex = 0;
        
        for (uint256 i = 0; i < allBounties.length; i++) {
            if (!bounties[allBounties[i]].claimed) {
                activeBounties[currentIndex] = allBounties[i];
                currentIndex++;
            }
        }
        
        return activeBounties;
    }
    
    // Get total active bounty value on a target
    function getTotalBountyOnTarget(address _target) external view returns (uint256) {
        uint256[] memory allBounties = bountiesOnTarget[_target];
        uint256 totalValue = 0;
        
        for (uint256 i = 0; i < allBounties.length; i++) {
            if (!bounties[allBounties[i]].claimed) {
                totalValue += bounties[allBounties[i]].amount;
            }
        }
        
        return totalValue;
    }
    
    // Emergency withdrawal (only owner, only if something goes wrong)
    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = payable(owner).call{value: address(this).balance}("");
        require(success, "Withdrawal failed");
    }
}
