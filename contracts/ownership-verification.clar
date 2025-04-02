;; ownership-verification.clar
;; A contract for verifying ownership of intellectual property

;; Error codes
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_ALREADY_VERIFIED (err u101))
(define-constant ERR_NOT_FOUND (err u102))
(define-constant ERR_INVALID_PROOF (err u103))

;; Data structures
(define-map ownership-verifications
  { creation-id: (buff 32) }
  {
    owner: principal,
    verification-level: uint,
    verification-method: (string-utf8 256),
    verified-at: uint,
    verifier: (optional principal),
    proof-hash: (buff 32)
  }
)

;; Define trusted verifiers
(define-map trusted-verifiers
  { verifier: principal }
  { active: bool }
)

;; Contract owner
(define-data-var contract-owner principal tx-sender)

;; Public functions
(define-public (verify-ownership
                (creation-id (buff 32))
                (owner principal)
                (verification-method (string-utf8 256))
                (proof-hash (buff 32)))
  (let ((caller tx-sender))
    ;; Only the owner can self-verify
    (asserts! (is-eq caller owner) ERR_NOT_AUTHORIZED)

    ;; Set verification level to 1 (self-verified)
    (map-set ownership-verifications
      { creation-id: creation-id }
      {
        owner: owner,
        verification-level: u1,
        verification-method: verification-method,
        verified-at: block-height,
        verifier: none,
        proof-hash: proof-hash
      }
    )

    (ok true)
  )
)

(define-public (verify-as-trusted-verifier
                (creation-id (buff 32))
                (owner principal)
                (verification-level uint)
                (verification-method (string-utf8 256))
                (proof-hash (buff 32)))
  (let ((caller tx-sender))
    ;; Check if the verifier is trusted
    (match (map-get? trusted-verifiers { verifier: caller })
      verifier-status (begin
        (asserts! (get active verifier-status) ERR_NOT_AUTHORIZED)

        ;; Set verification with trusted verifier status
        (map-set ownership-verifications
          { creation-id: creation-id }
          {
            owner: owner,
            verification-level: verification-level,
            verification-method: verification-method,
            verified-at: block-height,
            verifier: (some caller),
            proof-hash: proof-hash
          }
        )

        (ok true)
      )
      ERR_NOT_AUTHORIZED
    )
  )
)

;; Admin functions
(define-public (add-trusted-verifier (verifier principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (map-set trusted-verifiers
      { verifier: verifier }
      { active: true }
    )
    (ok true)
  )
)

(define-public (remove-trusted-verifier (verifier principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (map-set trusted-verifiers
      { verifier: verifier }
      { active: false }
    )
    (ok true)
  )
)

(define-public (transfer-contract-ownership (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (var-set contract-owner new-owner)
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-verification (creation-id (buff 32)))
  (map-get? ownership-verifications { creation-id: creation-id })
)

(define-read-only (is-trusted-verifier (verifier principal))
  (match (map-get? trusted-verifiers { verifier: verifier })
    status (get active status)
    false
  )
)

(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

