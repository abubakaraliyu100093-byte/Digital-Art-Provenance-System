;; Creator Royalty Automation Contract
;; Simplified, clean implementation for royalty setup and accounting

;; Errors
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-AMOUNT (err u201))
(define-constant ERR-INVALID-ROYALTY (err u202))
(define-constant ERR-NOT-FOUND (err u203))

;; State
(define-data-var paused bool false)
(define-data-var total-royalties uint u0)
(define-data-var sale-counter uint u0)

;; Storage
(define-map royalties
  uint
  {
    creator: principal,
    bps: uint,
    collected: uint,
    payments: uint
  }
)

(define-map earnings
  principal
  {
    accrued: uint,
    withdrawn: uint
  }
)

;; Read-only
(define-read-only (is-paused)
  (var-get paused)
)

(define-read-only (get-royalty (artwork-id uint))
  (map-get? royalties artwork-id)
)

(define-read-only (get-earnings (who principal))
  (default-to { accrued: u0, withdrawn: u0 } (map-get? earnings who))
)

(define-read-only (quote (artwork-id uint) (sale uint))
  (match (map-get? royalties artwork-id)
    r (ok (/ (* sale (get bps r)) u10000))
    (err ERR-NOT-FOUND)
  )
)

;; Admin
(define-public (pause)
  (begin (var-set paused true) (ok true))
)

(define-public (resume)
  (begin (var-set paused false) (ok true))
)

;; Setup royalty for an artwork
(define-public (setup (artwork-id uint) (creator principal) (bps uint))
  (begin
    (asserts! (not (var-get paused)) ERR-NOT-AUTHORIZED)
    (asserts! (<= bps u1000) ERR-INVALID-ROYALTY)
    (map-set royalties artwork-id { creator: creator, bps: bps, collected: u0, payments: u0 })
    (ok true)
  )
)

;; Process a secondary sale and accrue royalty
(define-public (record-sale (artwork-id uint) (seller principal) (buyer principal) (sale uint))
  (let ((royalty-opt (map-get? royalties artwork-id)))
    (asserts! (not (var-get paused)) ERR-NOT-AUTHORIZED)
    (asserts! (> sale u0) ERR-INVALID-AMOUNT)
    (asserts! (is-some royalty-opt) ERR-NOT-FOUND)
    
    (let ((r (unwrap-panic royalty-opt)))
      (let (
            (amount (/ (* sale (get bps r)) u10000))
            (creator (get creator r))
            (new-sale-id (+ (var-get sale-counter) u1))
          )
        (let ((e (get-earnings creator)))
          (map-set earnings creator { accrued: (+ (get accrued e) amount), withdrawn: (get withdrawn e) })
        )
        (map-set royalties artwork-id (merge r { collected: (+ (get collected r) amount), payments: (+ (get payments r) u1) }))
        (var-set sale-counter new-sale-id)
        (var-set total-royalties (+ (var-get total-royalties) amount))
        (ok new-sale-id)
      )
    )
  )
)

;; Withdraw accrued earnings from the contract
(define-public (withdraw (amount uint))
  (let ((who tx-sender) (e (get-earnings tx-sender)))
    (asserts! (not (var-get paused)) ERR-NOT-AUTHORIZED)
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (<= amount (get accrued e)) ERR-INVALID-AMOUNT)
    
    (unwrap! (stx-transfer? amount (as-contract tx-sender) who) ERR-INVALID-AMOUNT)
    (map-set earnings who { accrued: (- (get accrued e) amount), withdrawn: (+ (get withdrawn e) amount) })
    (ok amount)
  )
)
