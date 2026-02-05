/// PasaTanda Core Module Tests
/// Comprehensive unit tests for all tanda functionality
#[test_only]
module pasatanda_move_smartcontracts::pasatanda_core_tests;

use sui::test_scenario::{Self as ts, Scenario};
use sui::coin::{Self, Coin};
use sui::sui::SUI;
use sui::clock::{Self, Clock};
use pasatanda_move_smartcontracts::pasatanda_core::{
    Self,
    Tanda,
    TandaAdminCap,
    create_tanda,
    deposit_guarantee,
    deposit_payment,
    deposit_payment_for,
    payout_round,
    close_tanda,
    get_current_round,
    get_phase,
    get_contribution_amount,
    get_guarantee_amount,
    get_num_participants,
    get_admin,
    get_total_principal,
    get_participant_round_payment,
    has_paid_guarantee,
    get_current_beneficiary,
    get_principal_balance_value,
    get_guarantee_balance_value,
};

// Test addresses
const ADMIN: address = @0xAD;
const ALICE: address = @0xA1;
const BOB: address = @0xB0;
const CAROL: address = @0xCA;
const VAULT: address = @0xFA;

// Test amounts
const CONTRIBUTION_AMOUNT: u64 = 1000;
const GUARANTEE_AMOUNT: u64 = 500;

// ============================================
// HELPER FUNCTIONS
// ============================================

fun setup_scenario(): Scenario {
    ts::begin(ADMIN)
}

fun create_clock(scenario: &mut Scenario): Clock {
    ts::next_tx(scenario, ADMIN);
    clock::create_for_testing(ts::ctx(scenario))
}

fun mint_sui(amount: u64, ctx: &mut TxContext): Coin<SUI> {
    coin::mint_for_testing<SUI>(amount, ctx)
}

fun create_participants(): vector<address> {
    vector[ALICE, BOB, CAROL]
}

// ============================================
// TEST: TANDA CREATION
// ============================================

#[test]
fun test_create_tanda_success() {
    let mut scenario = setup_scenario();
    let clock = create_clock(&mut scenario);
    
    // Create tanda
    ts::next_tx(&mut scenario, ADMIN);
    {
        let participants = create_participants();
        create_tanda<SUI>(
            participants,
            CONTRIBUTION_AMOUNT,
            GUARANTEE_AMOUNT,
            option::some(VAULT),
            &clock,
            ts::ctx(&mut scenario)
        );
    };
    
    // Verify tanda was created
    ts::next_tx(&mut scenario, ADMIN);
    {
        let tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        
        assert!(get_current_round(&tanda) == 0, 0);
        assert!(get_phase(&tanda) == 0, 1); // PHASE_INITIALIZING
        assert!(get_contribution_amount(&tanda) == CONTRIBUTION_AMOUNT, 2);
        assert!(get_guarantee_amount(&tanda) == GUARANTEE_AMOUNT, 3);
        assert!(get_num_participants(&tanda) == 3, 4);
        assert!(get_admin(&tanda) == ADMIN, 5);
        
        ts::return_shared(tanda);
    };
    
    // Verify admin cap was created
    ts::next_tx(&mut scenario, ADMIN);
    {
        let admin_cap = ts::take_from_sender<TandaAdminCap>(&scenario);
        ts::return_to_sender(&scenario, admin_cap);
    };
    
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = pasatanda_core::E_INVALID_PARTICIPANTS)]
fun test_create_tanda_single_participant_fails() {
    let mut scenario = setup_scenario();
    let clock = create_clock(&mut scenario);
    
    ts::next_tx(&mut scenario, ADMIN);
    {
        let participants = vector[ALICE]; // Only one participant
        create_tanda<SUI>(
            participants,
            CONTRIBUTION_AMOUNT,
            GUARANTEE_AMOUNT,
            option::none(),
            &clock,
            ts::ctx(&mut scenario)
        );
    };
    
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = pasatanda_core::E_INVALID_AMOUNT)]
fun test_create_tanda_zero_contribution_fails() {
    let mut scenario = setup_scenario();
    let clock = create_clock(&mut scenario);
    
    ts::next_tx(&mut scenario, ADMIN);
    {
        let participants = create_participants();
        create_tanda<SUI>(
            participants,
            0, // Zero contribution
            GUARANTEE_AMOUNT,
            option::none(),
            &clock,
            ts::ctx(&mut scenario)
        );
    };
    
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ============================================
// TEST: GUARANTEE DEPOSITS
// ============================================

#[test]
fun test_deposit_guarantee_success() {
    let mut scenario = setup_scenario();
    let clock = create_clock(&mut scenario);
    
    // Create tanda
    ts::next_tx(&mut scenario, ADMIN);
    {
        let participants = create_participants();
        create_tanda<SUI>(
            participants,
            CONTRIBUTION_AMOUNT,
            GUARANTEE_AMOUNT,
            option::none(),
            &clock,
            ts::ctx(&mut scenario)
        );
    };
    
    // Alice deposits guarantee
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(GUARANTEE_AMOUNT, ts::ctx(&mut scenario));
        
        assert!(!has_paid_guarantee(&tanda, ALICE), 0);
        
        deposit_guarantee(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        
        assert!(has_paid_guarantee(&tanda, ALICE), 1);
        assert!(get_guarantee_balance_value(&tanda) == GUARANTEE_AMOUNT, 2);
        assert!(get_phase(&tanda) == 0, 3); // Still initializing (not all paid)
        
        ts::return_shared(tanda);
    };
    
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_all_guarantees_activates_tanda() {
    let mut scenario = setup_scenario();
    let clock = create_clock(&mut scenario);
    
    // Create tanda
    ts::next_tx(&mut scenario, ADMIN);
    {
        let participants = create_participants();
        create_tanda<SUI>(
            participants,
            CONTRIBUTION_AMOUNT,
            GUARANTEE_AMOUNT,
            option::none(),
            &clock,
            ts::ctx(&mut scenario)
        );
    };
    
    // Alice deposits guarantee
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(GUARANTEE_AMOUNT, ts::ctx(&mut scenario));
        deposit_guarantee(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    // Bob deposits guarantee
    ts::next_tx(&mut scenario, BOB);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(GUARANTEE_AMOUNT, ts::ctx(&mut scenario));
        deposit_guarantee(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    // Carol deposits guarantee - should activate
    ts::next_tx(&mut scenario, CAROL);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(GUARANTEE_AMOUNT, ts::ctx(&mut scenario));
        
        assert!(get_phase(&tanda) == 0, 0); // Still initializing
        
        deposit_guarantee(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        
        assert!(get_phase(&tanda) == 1, 1); // Now PHASE_ACTIVE
        assert!(get_guarantee_balance_value(&tanda) == GUARANTEE_AMOUNT * 3, 2);
        
        ts::return_shared(tanda);
    };
    
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = pasatanda_core::E_NOT_PARTICIPANT)]
fun test_deposit_guarantee_non_participant_fails() {
    let mut scenario = setup_scenario();
    let clock = create_clock(&mut scenario);
    
    // Create tanda
    ts::next_tx(&mut scenario, ADMIN);
    {
        let participants = vector[ALICE, BOB]; // CAROL not included
        create_tanda<SUI>(
            participants,
            CONTRIBUTION_AMOUNT,
            GUARANTEE_AMOUNT,
            option::none(),
            &clock,
            ts::ctx(&mut scenario)
        );
    };
    
    // Carol tries to deposit (not a participant)
    ts::next_tx(&mut scenario, CAROL);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(GUARANTEE_AMOUNT, ts::ctx(&mut scenario));
        deposit_guarantee(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = pasatanda_core::E_GUARANTEE_ALREADY_PAID)]
fun test_deposit_guarantee_twice_fails() {
    let mut scenario = setup_scenario();
    let clock = create_clock(&mut scenario);
    
    // Create tanda
    ts::next_tx(&mut scenario, ADMIN);
    {
        let participants = create_participants();
        create_tanda<SUI>(
            participants,
            CONTRIBUTION_AMOUNT,
            GUARANTEE_AMOUNT,
            option::none(),
            &clock,
            ts::ctx(&mut scenario)
        );
    };
    
    // Alice deposits guarantee
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(GUARANTEE_AMOUNT, ts::ctx(&mut scenario));
        deposit_guarantee(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    // Alice tries to deposit again
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(GUARANTEE_AMOUNT, ts::ctx(&mut scenario));
        deposit_guarantee(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ============================================
// TEST: ROUND PAYMENTS
// ============================================

fun setup_active_tanda(scenario: &mut Scenario, clock: &Clock) {
    // Create tanda
    ts::next_tx(scenario, ADMIN);
    {
        let participants = create_participants();
        create_tanda<SUI>(
            participants,
            CONTRIBUTION_AMOUNT,
            GUARANTEE_AMOUNT,
            option::some(VAULT),
            clock,
            ts::ctx(scenario)
        );
    };
    
    // All participants deposit guarantees
    ts::next_tx(scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(scenario);
        let payment = mint_sui(GUARANTEE_AMOUNT, ts::ctx(scenario));
        deposit_guarantee(&mut tanda, payment, clock, ts::ctx(scenario));
        ts::return_shared(tanda);
    };
    
    ts::next_tx(scenario, BOB);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(scenario);
        let payment = mint_sui(GUARANTEE_AMOUNT, ts::ctx(scenario));
        deposit_guarantee(&mut tanda, payment, clock, ts::ctx(scenario));
        ts::return_shared(tanda);
    };
    
    ts::next_tx(scenario, CAROL);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(scenario);
        let payment = mint_sui(GUARANTEE_AMOUNT, ts::ctx(scenario));
        deposit_guarantee(&mut tanda, payment, clock, ts::ctx(scenario));
        ts::return_shared(tanda);
    };
}

#[test]
fun test_deposit_payment_success() {
    let mut scenario = setup_scenario();
    let clock = create_clock(&mut scenario);
    
    setup_active_tanda(&mut scenario, &clock);
    
    // Alice makes a payment
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        
        assert!(get_participant_round_payment(&tanda, ALICE) == 0, 0);
        
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        
        assert!(get_participant_round_payment(&tanda, ALICE) == CONTRIBUTION_AMOUNT, 1);
        assert!(get_principal_balance_value(&tanda) == CONTRIBUTION_AMOUNT, 2);
        
        ts::return_shared(tanda);
    };
    
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_deposit_payment_for_relayer_pattern() {
    let mut scenario = setup_scenario();
    let clock = create_clock(&mut scenario);
    
    setup_active_tanda(&mut scenario, &clock);
    
    // ADMIN (acting as backend) pays for ALICE
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        
        // Deposit for Alice (relayer pattern)
        deposit_payment_for(&mut tanda, payment, ALICE, &clock, ts::ctx(&mut scenario));
        
        // Alice should have the credit, not ADMIN
        assert!(get_participant_round_payment(&tanda, ALICE) == CONTRIBUTION_AMOUNT, 0);
        assert!(get_participant_round_payment(&tanda, ADMIN) == 0, 1);
        
        ts::return_shared(tanda);
    };
    
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = pasatanda_core::E_TANDA_NOT_ACTIVE)]
fun test_deposit_payment_before_active_fails() {
    let mut scenario = setup_scenario();
    let clock = create_clock(&mut scenario);
    
    // Create tanda but don't activate
    ts::next_tx(&mut scenario, ADMIN);
    {
        let participants = create_participants();
        create_tanda<SUI>(
            participants,
            CONTRIBUTION_AMOUNT,
            GUARANTEE_AMOUNT,
            option::none(),
            &clock,
            ts::ctx(&mut scenario)
        );
    };
    
    // Try to make payment before tanda is active
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ============================================
// TEST: PAYOUT
// ============================================

#[test]
fun test_payout_round_crypto_success() {
    let mut scenario = setup_scenario();
    let clock = create_clock(&mut scenario);
    
    setup_active_tanda(&mut scenario, &clock);
    
    // All participants make payments for round 0
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    ts::next_tx(&mut scenario, BOB);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    ts::next_tx(&mut scenario, CAROL);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    // Alice (first in order) should be able to claim round 0
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        
        assert!(get_current_round(&tanda) == 0, 0);
        assert!(get_current_beneficiary(&tanda) == ALICE, 1);
        
        payout_round(&mut tanda, 0, &clock, ts::ctx(&mut scenario)); // 0 = CRYPTO
        
        assert!(get_current_round(&tanda) == 1, 2); // Round advanced
        assert!(get_current_beneficiary(&tanda) == BOB, 3); // Next beneficiary
        
        ts::return_shared(tanda);
    };
    
    // Alice should have received the payout
    ts::next_tx(&mut scenario, ALICE);
    {
        let payout = ts::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin::value(&payout) == CONTRIBUTION_AMOUNT * 3, 0); // 3 participants
        ts::return_to_sender(&scenario, payout);
    };
    
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
fun test_payout_round_fiat_success() {
    let mut scenario = setup_scenario();
    let clock = create_clock(&mut scenario);
    
    setup_active_tanda(&mut scenario, &clock);
    
    // All participants make payments
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    ts::next_tx(&mut scenario, BOB);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    ts::next_tx(&mut scenario, CAROL);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    // Alice requests FIAT withdrawal
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        
        payout_round(&mut tanda, 1, &clock, ts::ctx(&mut scenario)); // 1 = FIAT
        
        ts::return_shared(tanda);
    };
    
    // Vault should have received the payout
    ts::next_tx(&mut scenario, VAULT);
    {
        let payout = ts::take_from_sender<Coin<SUI>>(&scenario);
        assert!(coin::value(&payout) == CONTRIBUTION_AMOUNT * 3, 0);
        ts::return_to_sender(&scenario, payout);
    };
    
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = pasatanda_core::E_WRONG_TURN)]
fun test_payout_wrong_turn_fails() {
    let mut scenario = setup_scenario();
    let clock = create_clock(&mut scenario);
    
    setup_active_tanda(&mut scenario, &clock);
    
    // All participants make payments
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    ts::next_tx(&mut scenario, BOB);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    ts::next_tx(&mut scenario, CAROL);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    // BOB tries to claim (but it's Alice's turn)
    ts::next_tx(&mut scenario, BOB);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        payout_round(&mut tanda, 0, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = pasatanda_core::E_ROUND_NOT_COMPLETE)]
fun test_payout_incomplete_round_fails() {
    let mut scenario = setup_scenario();
    let clock = create_clock(&mut scenario);
    
    setup_active_tanda(&mut scenario, &clock);
    
    // Only Alice pays (not all participants)
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    // Alice tries to claim before round is complete
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        payout_round(&mut tanda, 0, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ============================================
// TEST: FULL TANDA CYCLE
// ============================================

#[test]
fun test_complete_tanda_cycle() {
    let mut scenario = setup_scenario();
    let clock = create_clock(&mut scenario);
    
    setup_active_tanda(&mut scenario, &clock);
    
    // === ROUND 0 (Alice's turn) ===
    
    // All pay
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    ts::next_tx(&mut scenario, BOB);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    ts::next_tx(&mut scenario, CAROL);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    // Alice claims
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        payout_round(&mut tanda, 0, &clock, ts::ctx(&mut scenario));
        assert!(get_current_round(&tanda) == 1, 0);
        ts::return_shared(tanda);
    };
    
    // === ROUND 1 (Bob's turn) ===
    
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    ts::next_tx(&mut scenario, BOB);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    ts::next_tx(&mut scenario, CAROL);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    // Bob claims
    ts::next_tx(&mut scenario, BOB);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        payout_round(&mut tanda, 0, &clock, ts::ctx(&mut scenario));
        assert!(get_current_round(&tanda) == 2, 0);
        ts::return_shared(tanda);
    };
    
    // === ROUND 2 (Carol's turn - last round) ===
    
    ts::next_tx(&mut scenario, ALICE);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    ts::next_tx(&mut scenario, BOB);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    ts::next_tx(&mut scenario, CAROL);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let payment = mint_sui(CONTRIBUTION_AMOUNT, ts::ctx(&mut scenario));
        deposit_payment(&mut tanda, payment, &clock, ts::ctx(&mut scenario));
        ts::return_shared(tanda);
    };
    
    // Carol claims
    ts::next_tx(&mut scenario, CAROL);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        payout_round(&mut tanda, 0, &clock, ts::ctx(&mut scenario));
        
        assert!(get_current_round(&tanda) == 3, 0);
        assert!(get_phase(&tanda) == 2, 1); // PHASE_COMPLETED
        
        ts::return_shared(tanda);
    };
    
    // === CLOSE TANDA ===
    
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        let admin_cap = ts::take_from_sender<TandaAdminCap>(&scenario);
        
        close_tanda(&mut tanda, &admin_cap, &clock, ts::ctx(&mut scenario));
        
        assert!(get_phase(&tanda) == 3, 0); // PHASE_CLOSED
        
        ts::return_shared(tanda);
        ts::return_to_sender(&scenario, admin_cap);
    };
    
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}

// ============================================
// TEST: VIEW FUNCTIONS
// ============================================

#[test]
fun test_view_functions() {
    let mut scenario = setup_scenario();
    let clock = create_clock(&mut scenario);
    
    // Create tanda
    ts::next_tx(&mut scenario, ADMIN);
    {
        let participants = create_participants();
        create_tanda<SUI>(
            participants,
            CONTRIBUTION_AMOUNT,
            GUARANTEE_AMOUNT,
            option::some(VAULT),
            &clock,
            ts::ctx(&mut scenario)
        );
    };
    
    ts::next_tx(&mut scenario, ADMIN);
    {
        let tanda = ts::take_shared<Tanda<SUI>>(&scenario);
        
        // Test all view functions
        assert!(get_current_round(&tanda) == 0, 0);
        assert!(get_phase(&tanda) == 0, 1);
        assert!(get_contribution_amount(&tanda) == CONTRIBUTION_AMOUNT, 2);
        assert!(get_guarantee_amount(&tanda) == GUARANTEE_AMOUNT, 3);
        assert!(get_num_participants(&tanda) == 3, 4);
        assert!(get_admin(&tanda) == ADMIN, 5);
        assert!(get_total_principal(&tanda) == 0, 6);
        assert!(get_current_beneficiary(&tanda) == ALICE, 7);
        assert!(!has_paid_guarantee(&tanda, ALICE), 8);
        assert!(get_participant_round_payment(&tanda, ALICE) == 0, 9);
        assert!(get_principal_balance_value(&tanda) == 0, 10);
        assert!(get_guarantee_balance_value(&tanda) == 0, 11);
        
        ts::return_shared(tanda);
    };
    
    clock::destroy_for_testing(clock);
    ts::end(scenario);
}
