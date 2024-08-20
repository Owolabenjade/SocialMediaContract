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
;; Data structure for storing user profile information
(define-map user-profiles {user: principal} {username: (string-ascii 32), bio: (string-ascii 256)})

;; Event for profile updates
(define-event profile-updated (user principal username (string-ascii 32) bio (string-ascii 256)))

;; Create or update a user profile
(define-public (set-profile (username (string-ascii 32)) (bio (string-ascii 256)))
    (begin
        (asserts! (> (len username) 0) ERR_INVALID_AMOUNT)
        (asserts! (> (len bio) 0) ERR_INVALID_AMOUNT)
        (map-set user-profiles {user: tx-sender} {username: username, bio: bio})
        (emit-event profile-updated tx-sender username bio)
        (ok true)
    )
)

;; Retrieve a user's profile
(define-read-only (get-profile (user principal))
    (match (map-get? user-profiles {user: user})
        profile (ok profile)
        (err ERR_PROFILE_NOT_FOUND)
    )
)

;; ========== Content Management ========== ;;
;; Data structure for storing user-generated content
(define-map user-content {content-id: uint} {owner: principal, content-url: (string-ascii 256)})

;; Variable to keep track of content IDs
(define-data-var content-counter uint 0)

;; Event for content creation and deletion
(define-event content-created (content-id uint owner principal content-url (string-ascii 256)))
(define-event content-deleted (content-id uint owner principal))

;; Create new content
(define-public (create-content (content-url (string-ascii 256)))
    (begin
        (asserts! (> (len content-url) 0) ERR_INVALID_AMOUNT)
        (var-set content-counter (+ (var-get content-counter) u1))
        (let ((new-content-id (var-get content-counter)))
            (map-set user-content {content-id: new-content-id} {owner: tx-sender, content-url: content-url})
            (emit-event content-created new-content-id tx-sender content-url)
            (ok new-content-id)
        )
    )
)

;; Retrieve content by ID
(define-read-only (get-content (content-id uint))
    (match (map-get? user-content {content-id: content-id})
        content (ok content)
        (err ERR_CONTENT_NOT_FOUND)
    )
)

;; Delete content
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
;; Data structure to store proposals
(define-data-var proposals (map uint 
                                 {proposer: principal, 
                                  description: (string-ascii 256), 
                                  votes-for: uint, 
                                  votes-against: uint, 
                                  executed: bool}))

;; A counter to keep track of proposal IDs
(define-data-var proposal-counter uint 0)

;; Quorum requirement for proposal execution (e.g., at least 100 votes)
(define-constant quorum-requirement uint 100)

;; Events for governance activities
(define-event proposal-created (proposal-id uint proposer principal description (string-ascii 256)))
(define-event vote-recorded (proposal-id uint voter principal support bool vote-weight uint))
(define-event proposal-executed (proposal-id uint))

;; Create a new proposal
(define-public (create-proposal (description (string-ascii 256)))
    (begin
        (asserts! (> (len description) 0) ERR_INVALID_AMOUNT)
        (var-set proposal-counter (+ (var-get proposal-counter) u1))
        (let ((new-proposal-id (var-get proposal-counter)))
            (map-insert proposals new-proposal-id 
                        {proposer: tx-sender, 
                         description: description, 
                         votes-for: u0, 
                         votes-against: u0, 
                         executed: false})
            (emit-event proposal-created new-proposal-id tx-sender description)
            (ok new-proposal-id)
        )
    )
)

;; Vote on a proposal
(define-public (vote (proposal-id uint) (support bool) (vote-weight uint))
    (begin
        (asserts! (> vote-weight 0) ERR_INVALID_AMOUNT)
        (match (map-get? proposals proposal-id)
            proposal
            (begin
                (asserts! (>= (ft-get-balance platform-token tx-sender) vote-weight) ERR_INSUFFICIENT_BALANCE)
                (if support
                    (map-set proposals proposal-id 
                             {proposer: (tuple-get proposer proposal), 
                              description: (tuple-get description proposal), 
                              votes-for: (+ (tuple-get votes-for proposal) vote-weight), 
                              votes-against: (tuple-get votes-against proposal), 
                              executed: (tuple-get executed proposal)})
                    (map-set proposals proposal-id 
                             {proposer: (tuple-get proposer proposal), 
                              description: (tuple-get description proposal), 
                              votes-for: (tuple-get votes-for proposal), 
                              votes-against: (+ (tuple-get votes-against proposal) vote-weight), 
                              executed: (tuple-get executed proposal)})
                )
                (emit-event vote-recorded proposal-id tx-sender support vote-weight)
                (ok true)
            )
            (err ERR_PROPOSAL_NOT_FOUND)
        )
    )
)

;; Execute a proposal if it passes
(define-public (execute-proposal (proposal-id uint))
    (begin
        (match (map-get? proposals proposal-id)
            proposal
            (if (and (not (tuple-get executed proposal)) 
                     (> (tuple-get votes-for proposal) (tuple-get votes-against proposal))
                     (>= (+ (tuple-get votes-for proposal) (tuple-get votes-against proposal)) quorum-requirement))
                (begin
                    (map-set proposals proposal-id 
                             {proposer: (tuple-get proposer proposal), 
                              description: (tuple-get description proposal), 
                              votes-for: (tuple-get votes-for proposal), 
                              votes-against: (tuple-get votes-against proposal), 
                              executed: true})
                    (emit-event proposal-executed proposal-id)
                    (ok "Proposal executed successfully")
                )
                (err ERR_CANNOT_EXECUTE_PROPOSAL)
            )
            (err ERR_PROPOSAL_NOT_FOUND)
        )
    )
)

;; ========== Token-Based Tipping and Subscription Mechanisms ========== ;;
;; Define a fee for subscription
(define-constant subscription-fee uint 100)

;; Events for tipping and subscription
(define-event tipped (recipient principal amount uint))
(define-event subscribed (user principal subscriber principal subscription-fee uint))

;; Function to tip another user
(define-public (tip-user (recipient principal) (amount uint))
    (begin
        (asserts! (>= (ft-get-balance platform-token tx-sender) amount) ERR_INSUFFICIENT_BALANCE)
        (ft-transfer? platform-token tx-sender recipient amount)
        (emit-event tipped recipient amount)
        (ok "Tip successful")
    )
)

;; Function to subscribe to another user's content
(define-public (subscribe (user principal))
    (begin
        (asserts! (>= (ft-get-balance platform-token tx-sender) subscription-fee) ERR_INSUFFICIENT_BALANCE)
        (ft-transfer? platform-token tx-sender user subscription-fee)
        (emit-event subscribed user tx-sender subscription-fee)
        (ok "Subscription successful")
    )
)

;; ========== Helper Functions ========== ;;
;; Helper function to check if content exists
(define-private (content-exists? (content-id uint))
    (is-some (map-get? user-content {content-id: content-id}))
)

;; Helper function to ensure only the owner can modify content
(define-private (only-owner (content-id uint))
    (asserts! (is-eq tx-sender (get (map-get user-content {content-id: content-id}) owner)) ERR_UNAUTHORIZED)
)

