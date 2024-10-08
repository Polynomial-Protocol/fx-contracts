//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Module that simply adds view functions to retrieve additional info from the election module, such as historical election info
/// @dev View functions add to contract size, since they bloat the Solidity function dispatcher
interface IElectionInspectorModule {
    // ---------------------------------------
    // View functions
    // ---------------------------------------

    /// @notice Returns the date in which the given epoch started
    function getEpochStartDateForIndex(uint256 epochIndex) external view returns (uint64);

    /// @notice Returns the date in which the given epoch ended
    function getEpochEndDateForIndex(uint256 epochIndex) external view returns (uint64);

    /// @notice Returns the date in which the Nomination period in the given epoch started
    function getNominationPeriodStartDateForIndex(
        uint256 epochIndex
    ) external view returns (uint64);

    /// @notice Returns the date in which the Voting period in the given epoch started
    function getVotingPeriodStartDateForIndex(uint256 epochIndex) external view returns (uint64);

    /// @notice Shows if a candidate was nominated in the given epoch
    function wasNominated(address candidate, uint256 epochIndex) external view returns (bool);

    /// @notice Returns a list of all nominated candidates in the given epoch
    function getNomineesAtEpoch(uint256 epochIndex) external view returns (address[] memory);

    /// @notice Returns if user has voted in the given election
    function hasVotedInEpoch(
        address user,
        uint256 chainId,
        uint256 epochIndex
    ) external view returns (bool);

    function getCandidateVotesInEpoch(
        address candidate,
        uint256 epochIndex
    ) external view returns (uint256);

    /// @notice Returns the winners of the given election
    function getElectionWinnersInEpoch(uint256 epochIndex) external view returns (address[] memory);
}
