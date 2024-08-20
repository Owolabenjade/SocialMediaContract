;; ==============================
;; Decentralized Social Media Platform Smart Contract
;; ==============================

;; ========== Constants for Error Codes ========== ;;
(define-constant ERR_UNAUTHORIZED u1004)
(define-constant ERR_PROFILE_NOT_FOUND u1002)
(define-constant ERR_CONTENT_NOT_FOUND u1003)
(define-constant ERR_INSUFFICIENT_BALANCE u1001)
(define-constant ERR_PROPOSAL_NOT_FOUND u1008)
(define-constant ERR_CANNOT_EXECUTE_PROPOSAL u1009)
(define-constant ERR_INVALID_AMOUNT u1010)
(define-constant ERR_RATE_LIMITED u1011)

;; ========== Platform Token Creation ========== ;;
(define-fungible-token platform-token)

;; Admin role for managing certain functions
(define-data-var admin principal tx-sender)

;; Event for admin changes
(define-event admin-changed (new-admin principal))

;; Function to change the admin
(define-public (set-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get admin)) ERR_UNAUTHORIZED)
        (var-set admin new-admin)
        (emit-event admin-changed new-admin)
        (ok new-admin)
    )
)

;; ========== User Profile Management ========== ;;
(define-constant MAX_USERNAME_LENGTH u20)
(define-constant MAX_BIO_LENGTH u100)

(define-map user-profiles {user: principal} {username: (string-ascii MAX_USERNAME_LENGTH), bio: (string-ascii MAX_BIO_LENGTH)})

(define-event profile-updated (user principal username (string-ascii MAX_USERNAME_LENGTH) bio (string-ascii MAX_BIO_LENGTH)))

(define-public (set-profile (username (string-ascii MAX_USERNAME_LENGTH)) (bio (string-ascii MAX_BIO_LENGTH)))
    (begin
        (let ((existing-profile (default-to {username: "", bio: ""} (map-get? user-profiles {user: tx-sender}))))
            (if (and 
                 (is-eq (get username existing-profile) username) 
                 (is-eq (get bio existing-profile) bio))
                (ok "No update required")
                (begin
                    (map-set user-profiles {user: tx-sender} {username: username, bio: bio})
                    (emit-event profile-updated tx-sender username bio)
                    (ok true)
                )
            )
        )
    )
)

(define-read-only (get-profile (user principal))
    (map-get? user-profiles {user: user})
)

;; ========== Content Management ========== ;;
(define-map user-content {content-id: uint} {owner: principal, content-url: (string-ascii 256)})

(define-data-var content-counter uint 0)

(define-event content-created (content-id uint owner principal content-url (string-ascii 256)))
(define-event content-deleted (content-id uint owner principal))

(define-public (create-content (content-url (string-ascii 256)))
    (begin
        (var-set content-counter (+ (var-get content-counter) u1))
        (let ((new-content-id (var-get content-counter)))
            (map-set user-content {content-id: new-content-id} {owner: tx-sender, content-url: content-url})
            (emit-event content-created new-content-id tx-sender content-url)
            (ok new-content-id)
        )
    )
)

(define-read-only (get-content (content-id uint))
    (map-get? user-content {content-id: content-id})
)

(define-public (delete-content (content-id uint))
    (begin
        (asserts! (is-some (map-get? user-content {content-id: content-id})) ERR_CONTENT_NOT_FOUND)
        (only-owner content-id)
        (map-delete user-content {content-id: content-id})
        (emit-event content-deleted content-id tx-sender)
        (ok true)
    )
)

;; ========== Governance Contract ========== ;;
(define-data-var proposals (map uint 
                                 {proposer: principal, 
                                  description: (string-ascii 256), 
                                  votes-for: uint, 
                                  votes-against: uint, 
                                  executed: bool}))

(define-data-var proposal-counter uint 0)

(define-constant quorum-requirement uint 100)

(define-event proposal-created (proposal-id uint proposer principal description (string-ascii 256)))
(define-event vote-recorded (proposal-id uint voter principal support bool vote-weight uint))
(define-event proposal-executed (proposal-id uint))

(define-public (create-proposal (description (string-ascii 256)))
    (begin
        (var-set proposal-counter (+ (var-get proposal-counter) u1))
        (let ((new-proposal-id (var-get proposal-counter)))
            (map-set proposals {proposal-id: new-proposal-id}
                     {proposer: tx-sender, description: description, votes-for: u0, votes-against: u0, executed: false})
            (emit-event proposal-created new-proposal-id tx-sender description)
            (ok new-proposal-id)
        )
    )
)

(define-public (vote (proposal-id uint) (support bool) (vote-weight uint))
    (begin
        (asserts! (> vote-weight 0) ERR_INVALID_AMOUNT)
        (let ((proposal (map-get? proposals {proposal-id: proposal-id})))
            (asserts! (is-some proposal) ERR_PROPOSAL_NOT_FOUND)
            (if support
                (map-set proposals {proposal-id: proposal-id}
                         {proposer: (get proposer proposal), 
                          description: (get description proposal), 
                          votes-for: (+ (get votes-for proposal) vote-weight), 
                          votes-against: (get votes-against proposal), 
                          executed: (get executed proposal)})
                (map-set proposals {proposal-id: proposal-id}
                         {proposer: (get proposer proposal), 
                          description: (get description proposal), 
                          votes-for: (get votes-for proposal), 
                          votes-against: (+ (get votes-against proposal) vote-weight), 
                          executed: (get executed proposal)})
            )
            (emit-event vote-recorded proposal-id tx-sender support vote-weight)
            (ok true)
        )
    )
)

(define-public (execute-proposal (proposal-id uint))
    (begin
        (let ((proposal (map-get? proposals {proposal-id: proposal-id})))
            (asserts! (is-some proposal) ERR_PROPOSAL_NOT_FOUND)
            (if (and (not (get executed proposal)) 
                     (> (get votes-for proposal) (get votes-against proposal))
                     (>= (+ (get votes-for proposal) (get votes-against proposal)) quorum-requirement))
                (begin
                    (map-set proposals {proposal-id: proposal-id}
                             {proposer: (get proposer proposal), 
                              description: (get description proposal), 
                              votes-for: (get votes-for proposal), 
                              votes-against: (get votes-against proposal), 
                              executed: true})
                    (emit-event proposal-executed proposal-id)
                    (ok "Proposal executed successfully")
                )
                (err ERR_CANNOT_EXECUTE_PROPOSAL)
            )
        )
    )
)

;; ========== Token-Based Tipping and Subscription Mechanisms ========== ;;
(define-constant subscription-fee uint 100)

(define-event tipped (recipient principal amount uint))
(define-event subscribed (user principal subscriber principal subscription-fee uint))

(define-public (tip-user (recipient principal) (amount uint))
    (begin
        (asserts! (>= (ft-get-balance platform-token tx-sender) amount) ERR_INSUFFICIENT_BALANCE)
        (ft-transfer? platform-token tx-sender recipient amount)
        (emit-event tipped recipient amount)
        (ok "Tip successful")
    )
)

(define-public (subscribe (user principal))
    (begin
        (asserts! (>= (ft-get-balance platform-token tx-sender) subscription-fee) ERR_INSUFFICIENT_BALANCE)
        (ft-transfer? platform-token tx-sender user subscription-fee)
        (emit-event subscribed user tx-sender subscription-fee)
        (ok "Subscription successful")
    )
)

;; ========== Helper Functions ========== ;;
(define-private (content-exists? (content-id uint))
    (is-some (map-get? user-content {content-id: content-id}))
)

(define-private (only-owner (content-id uint))
    (asserts! (is-eq tx-sender (get (map-get user-content {content-id: content-id}) owner)) ERR_UNAUTHORIZED)
)
