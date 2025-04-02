;; licensing-terms.clar
;; A contract for managing licensing terms for intellectual property

;; Error codes
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_ALREADY_EXISTS (err u101))
(define-constant ERR_NOT_FOUND (err u102))
(define-constant ERR_EXPIRED (err u103))
(define-constant ERR_PAYMENT_REQUIRED (err u104))

;; License types
(define-constant LICENSE_TYPE_EXCLUSIVE u1)
(define-constant LICENSE_TYPE_NON_EXCLUSIVE u2)
(define-constant LICENSE_TYPE_CREATIVE_COMMONS u3)
(define-constant LICENSE_TYPE_CUSTOM u4)

;; Data structures
(define-map license-templates
  { template-id: (buff 32) }
  {
    creator: principal,
    name: (string-utf8 256),
    description: (string-utf8 1024),
    license-type: uint,
    terms: (string-utf8 2048),
    created-at: uint
  }
)

(define-map licenses
  { license-id: (buff 32) }
  {
    creation-id: (buff 32),
    licensor: principal,
    licensee: principal,
    template-id: (optional (buff 32)),
    license-type: uint,
    terms: (string-utf8 2048),
    start-block: uint,
    end-block: (optional uint),
    payment-amount: uint,
    payment-asset: (optional principal),
    is-active: bool,
    metadata: (string-utf8 1024)
  }
)

(define-map creation-licenses
  { creation-id: (buff 32) }
  { license-ids: (list 100 (buff 32)) }
)

;; Public functions
(define-public (create-license-template
                (template-id (buff 32))
                (name (string-utf8 256))
                (description (string-utf8 1024))
                (license-type uint)
                (terms (string-utf8 2048)))
  (let ((caller tx-sender))
    (asserts! (is-none (map-get? license-templates { template-id: template-id })) ERR_ALREADY_EXISTS)

    (map-set license-templates
      { template-id: template-id }
      {
        creator: caller,
        name: name,
        description: description,
        license-type: license-type,
        terms: terms,
        created-at: block-height
      }
    )

    (ok template-id)
  )
)

(define-public (issue-license
                (license-id (buff 32))
                (creation-id (buff 32))
                (licensee principal)
                (license-type uint)
                (terms (string-utf8 2048))
                (end-block (optional uint))
                (payment-amount uint)
                (payment-asset (optional principal))
                (metadata (string-utf8 1024)))
  (let ((caller tx-sender))
    ;; Check if license already exists
    (asserts! (is-none (map-get? licenses { license-id: license-id })) ERR_ALREADY_EXISTS)

    ;; Create the license
    (map-set licenses
      { license-id: license-id }
      {
        creation-id: creation-id,
        licensor: caller,
        licensee: licensee,
        template-id: none,
        license-type: license-type,
        terms: terms,
        start-block: block-height,
        end-block: end-block,
        payment-amount: payment-amount,
        payment-asset: payment-asset,
        is-active: true,
        metadata: metadata
      }
    )

    ;; Add to creation licenses list
    (match (map-get? creation-licenses { creation-id: creation-id })
      existing-entry (map-set creation-licenses
                      { creation-id: creation-id }
                      { license-ids: (unwrap! (as-max-len? (append (get license-ids existing-entry) license-id) u100) ERR_NOT_AUTHORIZED) })
      (map-set creation-licenses
        { creation-id: creation-id }
        { license-ids: (list license-id) })
    )

    (ok license-id)
  )
)

(define-public (issue-license-from-template
                (license-id (buff 32))
                (creation-id (buff 32))
                (licensee principal)
                (template-id (buff 32))
                (end-block (optional uint))
                (payment-amount uint)
                (payment-asset (optional principal))
                (metadata (string-utf8 1024)))
  (let ((caller tx-sender))
    ;; Check if license already exists
    (asserts! (is-none (map-get? licenses { license-id: license-id })) ERR_ALREADY_EXISTS)

    ;; Get the template
    (match (map-get? license-templates { template-id: template-id })
      template (begin
        ;; Create the license
        (map-set licenses
          { license-id: license-id }
          {
            creation-id: creation-id,
            licensor: caller,
            licensee: licensee,
            template-id: (some template-id),
            license-type: (get license-type template),
            terms: (get terms template),
            start-block: block-height,
            end-block: end-block,
            payment-amount: payment-amount,
            payment-asset: payment-asset,
            is-active: true,
            metadata: metadata
          }
        )

        ;; Add to creation licenses list
        (match (map-get? creation-licenses { creation-id: creation-id })
          existing-entry (map-set creation-licenses
                          { creation-id: creation-id }
                          { license-ids: (unwrap! (as-max-len? (append (get license-ids existing-entry) license-id) u100) ERR_NOT_AUTHORIZED) })
          (map-set creation-licenses
            { creation-id: creation-id }
            { license-ids: (list license-id) })
        )

        (ok license-id)
      )
      ERR_NOT_FOUND
    )
  )
)

(define-public (revoke-license (license-id (buff 32)))
  (let ((caller tx-sender))
    (match (map-get? licenses { license-id: license-id })
      license (begin
        (asserts! (is-eq (get licensor license) caller) ERR_NOT_AUTHORIZED)

        ;; Update the license to inactive
        (map-set licenses
          { license-id: license-id }
          (merge license { is-active: false })
        )

        (ok true)
      )
      ERR_NOT_FOUND
    )
  )
)

;; Read-only functions
(define-read-only (get-license (license-id (buff 32)))
  (map-get? licenses { license-id: license-id })
)

(define-read-only (get-license-template (template-id (buff 32)))
  (map-get? license-templates { template-id: template-id })
)

(define-read-only (get-licenses-for-creation (creation-id (buff 32)))
  (match (map-get? creation-licenses { creation-id: creation-id })
    entry (ok (get license-ids entry))
    (ok (list))
  )
)

(define-read-only (is-license-valid (license-id (buff 32)))
  (match (map-get? licenses { license-id: license-id })
    license (begin
      (and
        (get is-active license)
        (match (get end-block license)
          end-height (< block-height end-height)
          true
        )
      )
    )
    false
  )
)

