;; Artwork Authenticity Verification Contract
;; Simplified, clean implementation for artwork registration and provenance

;; Errors
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ARTWORK-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-REGISTERED (err u102))
(define-constant ERR-INVALID-METADATA (err u103))
(define-constant ERR-INVALID-ROYALTY (err u104))
(define-constant ERR-INVALID-TRANSFER (err u105))

;; State
(define-data-var contract-paused bool false)
(define-data-var artwork-counter uint u0)

;; Storage
(define-map artworks
  uint
  {
    creator: principal,
    owner: principal,
    uri: (string-ascii 256),
    metadata-hash: (buff 32),
    royalty-bps: uint,
    verified: bool,
    transfers: uint
  }
)

(define-map metadata->id
  (buff 32)
  uint
)

;; Read-only helpers
(define-read-only (is-paused)
  (var-get contract-paused)
)

(define-read-only (get-artwork (id uint))
  (map-get? artworks id)
)

(define-read-only (get-id-by-metadata (metadata (buff 32)))
  (map-get? metadata->id metadata)
)

(define-read-only (next-id)
  (+ (var-get artwork-counter) u1)
)

(define-read-only (royalty-of (id uint) (sale uint))
  (match (map-get? artworks id)
    data (ok (/ (* sale (get royalty-bps data)) u10000))
    (err ERR-ARTWORK-NOT-FOUND)
  )
)

;; Admin
(define-public (pause)
  (begin (var-set contract-paused true) (ok true))
)

(define-public (resume)
  (begin (var-set contract-paused false) (ok true))
)

;; Register artwork
(define-public (register (uri (string-ascii 256)) (meta (buff 32)) (royalty-bps uint))
  (begin
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    (asserts! (> (len uri) u0) ERR-INVALID-METADATA)
    (asserts! (<= royalty-bps u1000) ERR-INVALID-ROYALTY)
    (asserts! (is-none (map-get? metadata->id meta)) ERR-ALREADY-REGISTERED)

    (let ((id (next-id)))
      (map-set artworks id {
        creator: tx-sender,
        owner: tx-sender,
        uri: uri,
        metadata-hash: meta,
        royalty-bps: royalty-bps,
        verified: true,
        transfers: u0
      })
      (map-set metadata->id meta id)
      (var-set artwork-counter id)
      (ok id)
    )
  )
)

;; Transfer ownership
(define-public (transfer (id uint) (from principal) (to principal))
  (let ((artwork-opt (map-get? artworks id)))
    (asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)
    (asserts! (not (is-eq from to)) ERR-INVALID-TRANSFER)
    (asserts! (is-some artwork-opt) ERR-ARTWORK-NOT-FOUND)
    
    (let ((data (unwrap-panic artwork-opt)))
      (asserts! (is-eq (get owner data) from) ERR-NOT-AUTHORIZED)
      (asserts! (is-eq tx-sender from) ERR-NOT-AUTHORIZED)
      (map-set artworks id (merge data { owner: to, transfers: (+ (get transfers data) u1) }))
      (ok true)
    )
  )
)

;; Verify metadata
(define-public (verify (id uint) (expected (buff 32)))
  (match (map-get? artworks id)
    data (ok (is-eq (get metadata-hash data) expected))
    (err ERR-ARTWORK-NOT-FOUND)
  )
)
