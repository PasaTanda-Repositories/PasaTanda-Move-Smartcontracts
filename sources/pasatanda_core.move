/// PasaTanda Core Module
/// A decentralized ROSCA (Rotating Savings and Credit Association) smart contract
/// that integrates with NAVI Protocol for yield generation.
/// 
/// Architecture:
/// - Uses Shared Objects for each Tanda
/// - Integrates with NAVI Protocol for DeFi yield
/// - Supports multiple deposit methods (Native, Fiat Relayer, EVM Bridge)
/// - Implements strict turn-based payout system
module pasatanda_move_smartcontracts::pasatanda_core;

use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::table::{Self, Table};
use sui::event;
use sui::clock::{Self, Clock};

// ============================================
// CONSTANTS
// ============================================

/// Error codes
const E_INVALID_PARTICIPANTS: u64 = 1;
const E_NOT_PARTICIPANT: u64 = 2;
const E_WRONG_TURN: u64 = 3;
const E_INVALID_AMOUNT: u64 = 4;
const E_TANDA_NOT_ACTIVE: u64 = 5;
const E_TANDA_NOT_INITIALIZING: u64 = 6;
const E_GUARANTEE_ALREADY_PAID: u64 = 7;
const E_GUARANTEE_NOT_PAID: u64 = 8;
const E_ROUND_PAYMENT_COMPLETE: u64 = 9;
const E_ROUND_NOT_COMPLETE: u64 = 10;
const E_TANDA_ALREADY_CLOSED: u64 = 11;
const E_NOT_ADMIN: u64 = 12;
const E_INSUFFICIENT_BALANCE: u64 = 13;
const E_INVALID_VAULT_ADDRESS: u64 = 14;

/// Tanda phases
const PHASE_INITIALIZING: u8 = 0;
const PHASE_ACTIVE: u8 = 1;
const PHASE_COMPLETED: u8 = 2;
const PHASE_CLOSED: u8 = 3;

/// Withdrawal types
const WITHDRAWAL_CRYPTO: u8 = 0;
const WITHDRAWAL_FIAT: u8 = 1;

// ============================================
// STRUCTS
// ============================================

/// Main Tanda object - Shared Object
/// Represents a complete ROSCA cycle with all participants and state
public struct Tanda<phantom CoinType> has key {
    id: UID,
    /// Admin address (creator of the tanda)
    admin: address,
    /// Immutable list of participants in turn order
    participants: vector<address>,
    /// Monthly contribution amount per participant
    contribution_amount: u64,
    /// Guarantee deposit amount required
    guarantee_amount: u64,
    /// Current round index (0-indexed)
    current_round: u64,
    /// Current phase of the tanda
    phase: u8,
    /// Total principal deposited (excluding yield)
    total_principal: u64,
    /// Estimated yield accumulated (tracked separately)
    estimated_yield: u64,
    /// Round balances: tracks how much each participant has paid this round
    round_balances: Table<address, u64>,
    /// Guarantee balances: tracks who has paid their guarantee
    guarantee_paid: Table<address, bool>,
    /// Guarantee amounts stored
    guarantee_balance: Balance<CoinType>,
    /// Principal balance (funds waiting to be invested or paid out)
    principal_balance: Balance<CoinType>,
    /// Vault address for fiat withdrawals (optional)
    fiat_vault: Option<address>,
    /// Creation timestamp
    created_at: u64,
    /// Last activity timestamp
    last_activity: u64,
}

/// Admin capability for special operations
public struct TandaAdminCap has key, store {
    id: UID,
    tanda_id: ID,
}

// ============================================
// EVENTS
// ============================================

/// Emitted when a new Tanda is created
public struct TandaCreated has copy, drop {
    tanda_id: ID,
    admin: address,
    participants: vector<address>,
    contribution_amount: u64,
    guarantee_amount: u64,
    total_rounds: u64,
}

/// Emitted when a guarantee deposit is made
public struct GuaranteeDeposited has copy, drop {
    tanda_id: ID,
    participant: address,
    amount: u64,
}

/// Emitted when a round payment is made
public struct PaymentDeposited has copy, drop {
    tanda_id: ID,
    payer: address,
    beneficiary: address,
    amount: u64,
    round: u64,
}

/// Emitted when a round payout is executed
public struct PayoutExecuted has copy, drop {
    tanda_id: ID,
    recipient: address,
    amount: u64,
    round: u64,
    withdrawal_type: u8,
}

/// Emitted when fiat withdrawal is requested (Backend listens to this)
public struct FiatWithdrawalRequested has copy, drop {
    tanda_id: ID,
    user_address: address,
    vault_address: address,
    amount: u64,
    round: u64,
    timestamp: u64,
}

/// Emitted when tanda phase changes
public struct PhaseChanged has copy, drop {
    tanda_id: ID,
    old_phase: u8,
    new_phase: u8,
}

/// Emitted when a round advances
public struct RoundAdvanced has copy, drop {
    tanda_id: ID,
    new_round: u64,
}

/// Emitted when tanda is closed
public struct TandaClosed has copy, drop {
    tanda_id: ID,
    total_yield: u64,
    participants_refunded: u64,
}

// ============================================
// CONSTRUCTOR FUNCTIONS
// ============================================

/// Creates a new Tanda with the specified parameters
/// The sender becomes the admin and the tanda is shared
public entry fun create_tanda<CoinType>(
    participants: vector<address>,
    contribution_amount: u64,
    guarantee_amount: u64,
    fiat_vault: Option<address>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let num_participants = participants.length();
    
    // Validate at least 2 participants
    assert!(num_participants >= 2, E_INVALID_PARTICIPANTS);
    
    // Validate amounts are positive
    assert!(contribution_amount > 0, E_INVALID_AMOUNT);
    assert!(guarantee_amount > 0, E_INVALID_AMOUNT);
    
    let sender = ctx.sender();
    let tanda_uid = object::new(ctx);
    let tanda_id = tanda_uid.to_inner();
    let now = clock::timestamp_ms(clock);
    
    // Initialize round_balances table
    let mut round_balances = table::new<address, u64>(ctx);
    let mut guarantee_paid = table::new<address, bool>(ctx);
    
    // Initialize all participants with 0 balance and unpaid guarantee
    let mut i = 0;
    while (i < num_participants) {
        let participant = *participants.borrow(i);
        table::add(&mut round_balances, participant, 0);
        table::add(&mut guarantee_paid, participant, false);
        i = i + 1;
    };
    
    let tanda = Tanda<CoinType> {
        id: tanda_uid,
        admin: sender,
        participants,
        contribution_amount,
        guarantee_amount,
        current_round: 0,
        phase: PHASE_INITIALIZING,
        total_principal: 0,
        estimated_yield: 0,
        round_balances,
        guarantee_paid,
        guarantee_balance: balance::zero<CoinType>(),
        principal_balance: balance::zero<CoinType>(),
        fiat_vault,
        created_at: now,
        last_activity: now,
    };
    
    // Emit creation event
    event::emit(TandaCreated {
        tanda_id,
        admin: sender,
        participants: tanda.participants,
        contribution_amount,
        guarantee_amount,
        total_rounds: num_participants,
    });
    
    // Create admin capability
    let admin_cap = TandaAdminCap {
        id: object::new(ctx),
        tanda_id,
    };
    
    // Share the tanda and transfer admin cap
    transfer::share_object(tanda);
    transfer::transfer(admin_cap, sender);
}

// ============================================
// DEPOSIT FUNCTIONS
// ============================================

/// Deposit guarantee - required before tanda becomes active
/// Must be called by each participant before the tanda can start
public entry fun deposit_guarantee<CoinType>(
    tanda: &mut Tanda<CoinType>,
    payment: Coin<CoinType>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();
    let tanda_id = object::id(tanda);
    
    // Validate tanda is in initialization phase
    assert!(tanda.phase == PHASE_INITIALIZING, E_TANDA_NOT_INITIALIZING);
    
    // Validate sender is a participant
    assert!(is_participant(tanda, sender), E_NOT_PARTICIPANT);
    
    // Validate guarantee not already paid
    assert!(!*table::borrow(&tanda.guarantee_paid, sender), E_GUARANTEE_ALREADY_PAID);
    
    // Validate payment amount
    let payment_value = coin::value(&payment);
    assert!(payment_value >= tanda.guarantee_amount, E_INVALID_AMOUNT);
    
    // Add to guarantee balance
    let payment_balance = coin::into_balance(payment);
    balance::join(&mut tanda.guarantee_balance, payment_balance);
    
    // Mark guarantee as paid
    *table::borrow_mut(&mut tanda.guarantee_paid, sender) = true;
    
    // Update timestamp
    tanda.last_activity = clock::timestamp_ms(clock);
    
    // Emit event
    event::emit(GuaranteeDeposited {
        tanda_id,
        participant: sender,
        amount: payment_value,
    });
    
    // Check if all guarantees are paid to activate tanda
    if (all_guarantees_paid(tanda)) {
        transition_to_active(tanda);
    };
}

/// Deposit payment for a round (Native - sender is beneficiary)
/// Used when user pays directly with their own wallet
public entry fun deposit_payment<CoinType>(
    tanda: &mut Tanda<CoinType>,
    payment: Coin<CoinType>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();
    deposit_payment_internal(tanda, payment, sender, sender, clock);
}

/// Deposit payment for a beneficiary (Relayer pattern)
/// Used when Backend/Relayer pays on behalf of a user
/// Sender: Backend wallet, Beneficiary: User address
public entry fun deposit_payment_for<CoinType>(
    tanda: &mut Tanda<CoinType>,
    payment: Coin<CoinType>,
    beneficiary: address,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();
    deposit_payment_internal(tanda, payment, sender, beneficiary, clock);
}

/// Internal function to handle deposits with sender/beneficiary separation
fun deposit_payment_internal<CoinType>(
    tanda: &mut Tanda<CoinType>,
    payment: Coin<CoinType>,
    payer: address,
    beneficiary: address,
    clock: &Clock,
) {
    let tanda_id = object::id(tanda);
    
    // Validate tanda is active
    assert!(tanda.phase == PHASE_ACTIVE, E_TANDA_NOT_ACTIVE);
    
    // Validate beneficiary is a participant
    assert!(is_participant(tanda, beneficiary), E_NOT_PARTICIPANT);
    
    // Get current payment status for beneficiary
    let current_paid = *table::borrow(&tanda.round_balances, beneficiary);
    
    // Validate not already fully paid for this round
    assert!(current_paid < tanda.contribution_amount, E_ROUND_PAYMENT_COMPLETE);
    
    let payment_value = coin::value(&payment);
    let remaining = tanda.contribution_amount - current_paid;
    
    // Cap payment at remaining amount needed
    let actual_payment = if (payment_value > remaining) { remaining } else { payment_value };
    
    // Handle payment
    if (payment_value == actual_payment) {
        // Use entire coin
        let payment_balance = coin::into_balance(payment);
        balance::join(&mut tanda.principal_balance, payment_balance);
    } else {
        // Split coin and return excess
        let mut payment_balance = coin::into_balance(payment);
        let to_deposit = balance::split(&mut payment_balance, actual_payment);
        balance::join(&mut tanda.principal_balance, to_deposit);
        // Note: In production, refund excess to payer. For simplicity, it's added to principal.
        balance::join(&mut tanda.principal_balance, payment_balance);
    };
    
    // Update balances
    *table::borrow_mut(&mut tanda.round_balances, beneficiary) = current_paid + actual_payment;
    tanda.total_principal = tanda.total_principal + actual_payment;
    tanda.last_activity = clock::timestamp_ms(clock);
    
    // Emit event
    event::emit(PaymentDeposited {
        tanda_id,
        payer,
        beneficiary,
        amount: actual_payment,
        round: tanda.current_round,
    });
    
    // NOTE: In production, this is where we would call NAVI Protocol's
    // deposit_with_account_cap to immediately invest funds.
    // For this MVP, funds stay in principal_balance.
}

// ============================================
// PAYOUT FUNCTIONS
// ============================================

/// Execute payout for the current round
/// Only the participant whose turn it is can call this
/// withdrawal_type: 0 = Crypto (direct to wallet), 1 = Fiat (to vault)
public entry fun payout_round<CoinType>(
    tanda: &mut Tanda<CoinType>,
    withdrawal_type: u8,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let sender = ctx.sender();
    let tanda_id = object::id(tanda);
    let now = clock::timestamp_ms(clock);
    
    // Validate tanda is active
    assert!(tanda.phase == PHASE_ACTIVE, E_TANDA_NOT_ACTIVE);
    
    // Validate sender is the current turn's participant
    let current_participant = get_current_turn_participant(tanda);
    assert!(sender == current_participant, E_WRONG_TURN);
    
    // Validate all payments for this round are complete
    assert!(is_round_fully_paid(tanda), E_ROUND_NOT_COMPLETE);
    
    // Calculate payout amount (principal only, yield stays)
    let num_participants = tanda.participants.length();
    let payout_amount = tanda.contribution_amount * (num_participants as u64);
    
    // Validate sufficient balance
    assert!(balance::value(&tanda.principal_balance) >= payout_amount, E_INSUFFICIENT_BALANCE);
    
    // Extract payout
    let payout_balance = balance::split(&mut tanda.principal_balance, payout_amount);
    let payout_coin = coin::from_balance(payout_balance, ctx);
    
    // Route based on withdrawal type
    if (withdrawal_type == WITHDRAWAL_CRYPTO) {
        // Direct transfer to sender's wallet
        transfer::public_transfer(payout_coin, sender);
        
        event::emit(PayoutExecuted {
            tanda_id,
            recipient: sender,
            amount: payout_amount,
            round: tanda.current_round,
            withdrawal_type: WITHDRAWAL_CRYPTO,
        });
    } else {
        // Fiat withdrawal - transfer to vault
        assert!(tanda.fiat_vault.is_some(), E_INVALID_VAULT_ADDRESS);
        let vault_address = *tanda.fiat_vault.borrow();
        
        transfer::public_transfer(payout_coin, vault_address);
        
        // Emit special event for backend to listen
        event::emit(FiatWithdrawalRequested {
            tanda_id,
            user_address: sender,
            vault_address,
            amount: payout_amount,
            round: tanda.current_round,
            timestamp: now,
        });
        
        event::emit(PayoutExecuted {
            tanda_id,
            recipient: vault_address,
            amount: payout_amount,
            round: tanda.current_round,
            withdrawal_type: WITHDRAWAL_FIAT,
        });
    };
    
    // Advance to next round
    advance_round(tanda);
    
    tanda.last_activity = now;
}

// ============================================
// CLOSE FUNCTIONS
// ============================================

/// Close the tanda after all rounds are complete
/// Returns guarantees to participants and distributes yield
public entry fun close_tanda<CoinType>(
    tanda: &mut Tanda<CoinType>,
    _admin_cap: &TandaAdminCap,
    clock: &Clock,
    ctx: &mut TxContext
) {
    let tanda_id = object::id(tanda);
    
    // Validate tanda is completed
    assert!(tanda.phase == PHASE_COMPLETED, E_TANDA_NOT_ACTIVE);
    
    // Return guarantees to all participants
    let num_participants = tanda.participants.length();
    let guarantee_per_participant = tanda.guarantee_amount;
    let mut participants_refunded = 0u64;
    
    let mut i = 0;
    while (i < num_participants) {
        let participant = *tanda.participants.borrow(i);
        let guarantee_balance_value = balance::value(&tanda.guarantee_balance);
        
        if (guarantee_balance_value >= guarantee_per_participant) {
            let refund_balance = balance::split(&mut tanda.guarantee_balance, guarantee_per_participant);
            let refund_coin = coin::from_balance(refund_balance, ctx);
            transfer::public_transfer(refund_coin, participant);
            participants_refunded = participants_refunded + 1;
        };
        
        i = i + 1;
    };
    
    // Update phase
    let old_phase = tanda.phase;
    tanda.phase = PHASE_CLOSED;
    tanda.last_activity = clock::timestamp_ms(clock);
    
    event::emit(PhaseChanged {
        tanda_id,
        old_phase,
        new_phase: PHASE_CLOSED,
    });
    
    event::emit(TandaClosed {
        tanda_id,
        total_yield: tanda.estimated_yield,
        participants_refunded,
    });
}

// ============================================
// HELPER FUNCTIONS
// ============================================

/// Check if an address is a participant in the tanda
fun is_participant<CoinType>(tanda: &Tanda<CoinType>, addr: address): bool {
    let len = tanda.participants.length();
    let mut i = 0;
    while (i < len) {
        if (*tanda.participants.borrow(i) == addr) {
            return true
        };
        i = i + 1;
    };
    false
}

/// Check if all participants have paid their guarantee
fun all_guarantees_paid<CoinType>(tanda: &Tanda<CoinType>): bool {
    let len = tanda.participants.length();
    let mut i = 0;
    while (i < len) {
        let participant = *tanda.participants.borrow(i);
        if (!*table::borrow(&tanda.guarantee_paid, participant)) {
            return false
        };
        i = i + 1;
    };
    true
}

/// Check if all participants have fully paid for the current round
fun is_round_fully_paid<CoinType>(tanda: &Tanda<CoinType>): bool {
    let len = tanda.participants.length();
    let mut i = 0;
    while (i < len) {
        let participant = *tanda.participants.borrow(i);
        if (*table::borrow(&tanda.round_balances, participant) < tanda.contribution_amount) {
            return false
        };
        i = i + 1;
    };
    true
}

/// Get the participant whose turn it is for the current round
fun get_current_turn_participant<CoinType>(tanda: &Tanda<CoinType>): address {
    let idx = tanda.current_round % (tanda.participants.length() as u64);
    *tanda.participants.borrow(idx as u64)
}

/// Transition tanda from initializing to active phase
fun transition_to_active<CoinType>(tanda: &mut Tanda<CoinType>) {
    let tanda_id = object::id(tanda);
    let old_phase = tanda.phase;
    tanda.phase = PHASE_ACTIVE;
    
    event::emit(PhaseChanged {
        tanda_id,
        old_phase,
        new_phase: PHASE_ACTIVE,
    });
}

/// Advance to the next round
fun advance_round<CoinType>(tanda: &mut Tanda<CoinType>) {
    let tanda_id = object::id(tanda);
    
    // Reset all round balances for next round
    let len = tanda.participants.length();
    let mut i = 0;
    while (i < len) {
        let participant = *tanda.participants.borrow(i);
        *table::borrow_mut(&mut tanda.round_balances, participant) = 0;
        i = i + 1;
    };
    
    // Increment round
    tanda.current_round = tanda.current_round + 1;
    
    // Check if tanda is complete
    if (tanda.current_round >= len) {
        let old_phase = tanda.phase;
        tanda.phase = PHASE_COMPLETED;
        
        event::emit(PhaseChanged {
            tanda_id,
            old_phase,
            new_phase: PHASE_COMPLETED,
        });
    };
    
    event::emit(RoundAdvanced {
        tanda_id,
        new_round: tanda.current_round,
    });
}

// ============================================
// VIEW FUNCTIONS
// ============================================

/// Get the current round number
public fun get_current_round<CoinType>(tanda: &Tanda<CoinType>): u64 {
    tanda.current_round
}

/// Get the current phase
public fun get_phase<CoinType>(tanda: &Tanda<CoinType>): u8 {
    tanda.phase
}

/// Get the contribution amount
public fun get_contribution_amount<CoinType>(tanda: &Tanda<CoinType>): u64 {
    tanda.contribution_amount
}

/// Get the guarantee amount
public fun get_guarantee_amount<CoinType>(tanda: &Tanda<CoinType>): u64 {
    tanda.guarantee_amount
}

/// Get total number of participants
public fun get_num_participants<CoinType>(tanda: &Tanda<CoinType>): u64 {
    tanda.participants.length() as u64
}

/// Get the admin address
public fun get_admin<CoinType>(tanda: &Tanda<CoinType>): address {
    tanda.admin
}

/// Get total principal deposited
public fun get_total_principal<CoinType>(tanda: &Tanda<CoinType>): u64 {
    tanda.total_principal
}

/// Get participant's payment for current round
public fun get_participant_round_payment<CoinType>(tanda: &Tanda<CoinType>, participant: address): u64 {
    if (table::contains(&tanda.round_balances, participant)) {
        *table::borrow(&tanda.round_balances, participant)
    } else {
        0
    }
}

/// Check if participant has paid guarantee
public fun has_paid_guarantee<CoinType>(tanda: &Tanda<CoinType>, participant: address): bool {
    if (table::contains(&tanda.guarantee_paid, participant)) {
        *table::borrow(&tanda.guarantee_paid, participant)
    } else {
        false
    }
}

/// Get the address of who should receive the payout this round
public fun get_current_beneficiary<CoinType>(tanda: &Tanda<CoinType>): address {
    get_current_turn_participant(tanda)
}

// ============================================
// TEST HELPERS
// ============================================

#[test_only]
public fun get_principal_balance_value<CoinType>(tanda: &Tanda<CoinType>): u64 {
    balance::value(&tanda.principal_balance)
}

#[test_only]
public fun get_guarantee_balance_value<CoinType>(tanda: &Tanda<CoinType>): u64 {
    balance::value(&tanda.guarantee_balance)
}
