;; ==============================
;; Decentralized Social Media Platform Smart Contract
;; ==============================

;; ========== Platform Token Creation ========== ;;
(define-fungible-token platform-token)

;; Admin role for managing certain functions
(define-data-var admin principal tx-sender)

;; Function to change the admin
(define-public (set-admin (new-admin principal))
    (begin
        ;; Ensure only the current admin can change the admin role
        (asserts! (is-eq tx-sender (var-get admin)) (err u1004)) ;; Error code for "Unauthorized action"
        ;; Set the new admin
        (var-set admin new-admin)
        (print (concat "Admin role changed to " (principal-to-string new-admin)))
        (ok new-admin)
    )
)

;; ========== User Profile Management ========== ;;
;; Data structure for storing user profile information
(define-map user-profiles {user: principal} {username: (string-ascii 32), bio: (string-ascii 256)})

;; Create or update a user profile
(define-public (set-profile (username (string-ascii 32)) (bio (string-ascii 256)))
    (begin
        (map-set user-profiles {user: tx-sender} {username: username, bio: bio})
        (print (concat "Profile updated for user " (principal-to-string tx-sender)))
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

;; Create new content
(define-public (create-content (content-url (string-ascii 256)))
    (begin
        ;; Increment the content counter to generate a new content ID
        (var-set content-counter (+ (var-get content-counter) u1))
        (let ((new-content-id (var-get content-counter)))
            (map-set user-content {content-id: new-content-id} {owner: tx-sender, content-url: content-url})
            (print (concat "Content created with ID " (uint-to-string new-content-id) " by " (principal-to-string tx-sender)))
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
        (print (concat "Content with ID " (uint-to-string content-id) " deleted by " (principal-to-string tx-sender)))
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
            (print (concat "Proposal created with ID " (uint-to-string new-proposal-id) " by " (principal-to-string tx-sender)))
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
                (print (concat "Vote recorded on proposal ID " (uint-to-string proposal-id) " by " (principal-to-string tx-sender) " with " (uint-to-string vote-weight) " tokens"))
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
                    (print (concat "Executed proposal ID " (uint-to-string proposal-id)))
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

;; Function to tip another user
(define-public (tip-user (recipient principal) (amount uint))
    (begin
        ;; Ensure the sender has sufficient tokens
        (asserts! (>= (ft-get-balance platform-token tx-sender) amount) (err u1001)) ;; Error code for "Insufficient balance"
        ;; Transfer tokens to the recipient
        (ft-transfer? platform-token tx-sender recipient amount)
        (print (concat "Tipped " (uint-to-string amount) " tokens to " (principal-to-string recipient)))
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
        (print (concat "Subscribed to user " (principal-to-string user) " with a fee of " (uint-to-string subscription-fee) " tokens"))
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
    (begin
        (match (map-get? user-content {content-id: content-id})
            content
            (if (is-eq (tuple-get owner content) tx-sender)
                (ok true)
                (err u1005) ;; Error code for "Unauthorized action"
            )
            (err u1003) ;; Error code for "Content not found"
        )
    )
)
