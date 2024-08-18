;; ==============================
;; Decentralized Social Media Platform Smart Contract
;; ==============================

;; ========== Platform Token Creation ========== ;;
(define-fungible-token platform-token)

;; Admin role for managing certain functions
(define-data-var admin principal tx-sender)

;; Event for admin changes
(define-event admin-changed (new-admin principal))

;; Function to change the admin
(define-public (set-admin (new-admin principal))
    (begin
        ;; Ensure only the current admin can change the admin role
        (asserts! (is-eq tx-sender (var-get admin)) (err u1004)) ;; Error code for "Unauthorized action"
        ;; Set the new admin
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
        (map-set user-profiles {user: tx-sender} {username: username, bio: bio})
        (emit-event profile-updated tx-sender username bio)
        (ok {username: username, bio: bio})
    )
)

;; Retrieve a user's profile
(define-read-only (get-profile (user principal))
    (match (map-get? user-profiles {user: user})
        profile (ok profile)
        (err u1002) ;; Error code for "Profile not found"
    )
)

;; ========== Content Management ========== ;;
;; Data structure for storing user-generated content
(define-map user-content {content-id: uint} {owner: principal, content-url: (string-ascii 256)})

;; Variable to keep track of content IDs
(define-data-var content-counter uint 0)

;; Event for content creation
(define-event content-created (content-id uint owner principal content-url (string-ascii 256)))

;; Event for content deletion
(define-event content-deleted (content-id uint owner principal))

;; Create new content
(define-public (create-content (content-url (string-ascii 256)))
    (begin
        ;; Increment the content counter to generate a new content ID
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
        (err u1003) ;; Error code for "Content not found"
    )
)

;; Delete content
(define-public (delete-content (content-id uint))
    (begin
        ;; Ensure only the owner can delete the content
        (only-owner content-id)
        (map-delete user-content {content-id: content-id})
        (emit-event content-deleted content-id tx-sender)
        (ok true)
    )
)

;; ========== Governance Contract ========== ;;
;; This section handles platform governance, allowing token holders to propose changes and vote on them.

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

;; Event for proposal creation
(define-event proposal-created (proposal-id uint proposer principal description (string-ascii 256)))

;; Event for voting
(define-event vote-recorded (proposal-id uint voter principal support bool vote-weight uint))

;; Event for proposal execution
(define-event proposal-executed (proposal-id uint))

;; Create a new proposal
(define-public (create-proposal (description (string-ascii 256)))
    (begin
        ;; Increment the proposal counter to generate a new proposal ID
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
        ;; Ensure the proposal exists
        (match (map-get? proposals proposal-id)
            proposal
            (begin
                ;; Ensure the voter has enough tokens
                (asserts! (>= (ft-get-balance platform-token tx-sender) vote-weight) (err u1001)) ;; Error code for "Insufficient balance"
                ;; Update the vote count
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
                (ok "Vote recorded")
            )
            (err u1008) ;; Error code for "Proposal not found"
        )
    )
)

;; Execute a proposal if it passes
(define-public (execute-proposal (proposal-id uint))
    (begin
        ;; Ensure the proposal exists and hasn't been executed
        (match (map-get? proposals proposal-id)
            proposal
            (if (and (not (tuple-get executed proposal)) 
                     (> (tuple-get votes-for proposal) (tuple-get votes-against proposal))
                     (>= (+ (tuple-get votes-for proposal) (tuple-get votes-against proposal)) quorum-requirement))
                (begin
                    ;; Mark the proposal as executed
                    (map-set proposals proposal-id 
                             {proposer: (tuple-get proposer proposal), 
                              description: (tuple-get description proposal), 
                              votes-for: (tuple-get votes-for proposal), 
                              votes-against: (tuple-get votes-against proposal), 
                              executed: true})
                    ;; Execute the proposal's logic here (this is a placeholder)
                    ;; Example: upgrading the platform, changing rules, etc.
                    (emit-event proposal-executed proposal-id)
                    (ok "Proposal executed successfully")
                )
                (err u1009) ;; Error code for "Proposal cannot be executed"
            )
            (err u1008) ;; Error code for "Proposal not found"
        )
    )
)

;; ========== Token-Based Tipping and Subscription Mechanisms ========== ;;
;; Define a fee for subscription
(define-constant subscription-fee uint 100)

;; Event for tipping
(define-event tipped (recipient principal amount uint))

;; Event for subscription
(define-event subscribed (user principal subscriber principal subscription-fee uint))

;; Function to tip another user
(define-public (tip-user (recipient principal) (amount uint))
    (begin
        ;; Ensure the sender has sufficient tokens
        (asserts! (>= (ft-get-balance platform-token tx-sender) amount) (err u1001)) ;; Error code for "Insufficient balance"
        ;; Transfer tokens to the recipient
        (ft-transfer? platform-token tx-sender recipient amount)
        (emit-event tipped recipient amount)
        (ok "Tip successful")
    )
)

;; Function to subscribe to another user's content
(define-public (subscribe (user principal))
    (begin
        ;; Ensure the sender has sufficient tokens for the subscription fee
        (asserts! (>= (ft-get-balance platform-token tx-sender) subscription-fee) (err u1001)) ;; Error code for "Insufficient balance"
        ;; Transfer subscription fee to the user's account
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
    (asserts! (is-eq tx-sender (get (map-get user-content {content-id: content-id}) owner)) (err u1005)) ;; Error code for "Unauthorized action"
)
