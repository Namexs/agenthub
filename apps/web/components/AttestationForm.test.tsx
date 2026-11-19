// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { render, screen, fireEvent, cleanup } from '@testing-library/react';
import { AttestationForm } from './AttestationForm';

// PHASE 6 (R-010): component tests for the multi-signature
// AttestationForm. The hooks are mocked — the real verification logic
// is unit-tested in lib/attestation.test.ts and hooks/hooks.test.tsx;
// these tests pin the FORM wiring: threshold display, N signature
// inputs, verify -> submit flow with a signature array.

const mocks = vi.hoisted(() => ({
  check: vi.fn(),
  completeWithAttestation: vi.fn(),
  verification: {
    valid: false,
    signer: null as `0x${string}` | null,
    signers: [] as `0x${string}`[],
    perSigner: [] as {
      index: number;
      signer: `0x${string}` | null;
      valid: boolean;
      errors: string[];
      isVerifier: boolean | null;
    }[],
    errors: [] as string[],
    isVerifier: null as boolean | null,
    isCheckingRole: false,
    nonce: 1,
    nonceLoading: false,
    threshold: 2,
  },
  completeState: {
    hash: undefined as `0x${string}` | undefined,
    isPending: false,
    isConfirming: false,
    isSuccess: false,
    isFailed: false,
    error: null as string | null,
  },
}));

vi.mock('@/hooks/useChainGuard', () => ({
  useChainGuard: () => ({ isSupported: true }),
}));

vi.mock('@/hooks/useAttestation', () => ({
  useAttestation: () => ({
    check: mocks.check,
    verification: mocks.verification,
    reset: vi.fn(),
  }),
}));

vi.mock('@/hooks/useCompleteQuest', () => ({
  useCompleteQuest: () => ({
    completeWithAttestation: mocks.completeWithAttestation,
    ...mocks.completeState,
  }),
}));

vi.mock('@/lib/env', () => ({
  env: { NEXT_PUBLIC_CHAIN_ID: 97 },
}));

const SIG1 = `0x${'ab'.repeat(65)}`;
const SIG2 = `0x${'cd'.repeat(65)}`;
const DEADLINE = '1797000000';
const VERIFIER1 = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8' as `0x${string}`;
const VERIFIER2 = '0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC' as `0x${string}`;

function resetVerification() {
  mocks.verification.valid = false;
  mocks.verification.signer = null;
  mocks.verification.signers = [];
  mocks.verification.perSigner = [];
  mocks.verification.errors = [];
  mocks.verification.isVerifier = null;
  mocks.verification.isCheckingRole = false;
  mocks.verification.nonce = 1;
  mocks.verification.nonceLoading = false;
}

describe('AttestationForm (multi-signature)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    resetVerification();
  });

  // Vitest runs without globals, so @testing-library/react's
  // auto-cleanup is not registered — unmount explicitly, or renders
  // from earlier tests pollute later queries.
  afterEach(() => cleanup());

  it('shows the threshold and one input per required signature', () => {
    render(<AttestationForm questId={3} questTitle="Post on X" threshold={2} />);
    expect(screen.getByText(/requires 2 verifier signatures/)).toBeTruthy();
    expect(screen.getByLabelText('Signature 1 (65-byte 0x hex)')).toBeTruthy();
    expect(screen.getByLabelText('Signature 2 (65-byte 0x hex)')).toBeTruthy();
    expect(screen.queryByLabelText('Signature 3 (65-byte 0x hex)')).toBeNull();
  });

  it('renders a single input for a threshold-1 quest', () => {
    render(<AttestationForm questId={4} questTitle="Daily Post" threshold={1} />);
    expect(screen.getByText(/requires 1 verifier signature/)).toBeTruthy();
    expect(screen.getByLabelText('Signature 1 (65-byte 0x hex)')).toBeTruthy();
    expect(screen.queryByLabelText('Signature 2 (65-byte 0x hex)')).toBeNull();
  });

  it('lets the user add signature inputs up to 5', () => {
    render(<AttestationForm questId={3} questTitle="Post on X" threshold={2} />);
    fireEvent.click(screen.getByRole('button', { name: /Add another signature/ }));
    expect(screen.getByLabelText('Signature 3 (65-byte 0x hex)')).toBeTruthy();
    fireEvent.click(screen.getByRole('button', { name: /Add another signature/ }));
    fireEvent.click(screen.getByRole('button', { name: /Add another signature/ }));
    expect(screen.getByLabelText('Signature 5 (65-byte 0x hex)')).toBeTruthy();
    expect(screen.queryByRole('button', { name: /Add another signature/ })).toBeNull();
  });

  it('verifies the pair, then enables submit with both signatures', () => {
    const { rerender } = render(
      <AttestationForm questId={3} questTitle="Post on X" threshold={2} />,
    );
    fireEvent.change(screen.getByLabelText('Signature 1 (65-byte 0x hex)'), {
      target: { value: SIG1 },
    });
    fireEvent.change(screen.getByLabelText('Signature 2 (65-byte 0x hex)'), {
      target: { value: SIG2 },
    });
    fireEvent.change(screen.getByLabelText('Deadline (Unix timestamp, seconds)'), {
      target: { value: DEADLINE },
    });

    const submit = screen.getByRole('button', { name: 'Submit attestation' });
    expect(submit.hasAttribute('disabled')).toBe(true);

    fireEvent.click(screen.getByRole('button', { name: 'Verify attestation' }));
    expect(mocks.check).toHaveBeenCalledWith([SIG1, SIG2], Number(DEADLINE), 2);

    // The hook reports both signers verified — submit enables.
    mocks.verification.valid = true;
    mocks.verification.signers = [VERIFIER1, VERIFIER2];
    mocks.verification.isVerifier = true;
    mocks.verification.perSigner = [
      { index: 0, signer: VERIFIER1, valid: true, errors: [], isVerifier: true },
      { index: 1, signer: VERIFIER2, valid: true, errors: [], isVerifier: true },
    ];
    rerender(<AttestationForm questId={3} questTitle="Post on X" threshold={2} />);

    expect(screen.getAllByText('(verified verifier ✓)')).toHaveLength(2);
    expect(submit.hasAttribute('disabled')).toBe(false);
    fireEvent.click(submit);
    expect(mocks.completeWithAttestation).toHaveBeenCalledWith(3, Number(DEADLINE), [SIG1, SIG2]);
  });
});
