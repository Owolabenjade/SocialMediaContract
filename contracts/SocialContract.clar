;; ========== Platform Token Creation ========== ;;
;; Define the platform token. This example uses a basic fungible token implementation.
(define-fungible-token platform-token 1000000) ;; Total supply of 1,000,000 tokens

;; Define the admin role and allow admin transfer
(define-data-var admin principal tx-sender)

;; Function to change the admin
(define-public (change-admin (new-admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get admin)) (err u1010)) ;; Error code for "Unauthorized admin change"
        (var-set admin new-admin)
        (print (concat "Admin changed to " (principal-to-string new-admin)))
        (ok "Admin changed successfully")
    )
)

;; Mint new tokens to a user. Typically, this would be restricted to certain roles.
(define-public (mint-tokens (recipient principal) (amount uint))
    (begin
        ;; Ensure only an authorized user can mint tokens (admin)
        (asserts! (is-eq tx-sender (var-get admin)) (err u1000)) ;; Error code for "Unauthorized action"
        (try! (ft-mint? platform-token amount recipient))
        (print (concat "Minted " (uint-to-string amount) " tokens to " (principal-to-string recipient)))
        (ok amount)
    )
)

;; Allow a user to transfer tokens to another user.
(define-public (transfer-tokens (recipient principal) (amount uint))
    (begin
        ;; Ensure sender has enough balance (this is automatically handled by ft-transfer? but good to check)
        (asserts! (>= (ft-get-balance platform-token tx-sender) amount) (err u1001)) ;; Error code for "Insufficient balance"
        (try! (ft-transfer? platform-token amount tx-sender recipient))
        (print (concat "Transferred " (uint-to-string amount) " tokens to " (principal-to-string recipient)))
        (ok amount)
    )
)

;; ========== User Profile Data Storage and Management ========== ;;
(define-data-var user-profiles (map principal 
                                  {username: (string-ascii 32), 
                                   bio: (optional (string-ascii 160)), 
                                   profile-pic-url: (optional (string-ascii 256))}))

;; Create a user profile
(define-public (create-profile (username (string-ascii 32)) 
                               (bio (optional (string-ascii 160))) 
                               (profile-pic-url (optional (string-ascii 256))))
    (begin
        ;; Ensure the user doesn't already have a profile
        (asserts! (not (map-get? user-profiles tx-sender)) (err u1002)) ;; Error code for "Profile already exists"
        (map-insert user-profiles tx-sender 
                    {username: username, bio: bio, profile-pic-url: profile-pic-url})
        (print "Profile created successfully")
        (ok "Profile created successfully")
    )
)

;; Update an existing user profile
(define-public (update-profile (username (string-ascii 32)) 
                               (bio (optional (string-ascii 160))) 
                               (profile-pic-url (optional (string-ascii 256))))
    (begin
        ;; Ensure the profile exists
        (asserts! (map-get? user-profiles tx-sender) (err u1003)) ;; Error code for "Profile not found"
        (map-set user-profiles tx-sender 
                 {username: username, bio: bio, profile-pic-url: profile-pic-url})
        (print "Profile updated successfully")
        (ok "Profile updated successfully")
    )
)

;; Get a user profile
(define-read-only (get-profile (user principal))
    (map-get? user-profiles user)
)

;; ========== On-Chain Content Reference Storage and Access Control ========== ;;
(define-data-var user-content (map {content-id: uint} 
                                  {owner: principal, 
                                   content-url: (string-ascii 256), 
                                   access-control: (list 100 principal)}))

;; Upload new content to the blockchain
(define-public (upload-content (content-id uint) 
                               (content-url (string-ascii 256)) 
                               (access-control (list 100 principal)))
    (begin
        ;; Ensure the content ID is unique
        (asserts! (not (content-exists? content-id)) (err u1004)) ;; Error code for "Content ID already exists"
        (map-insert user-content {content-id: content-id} 
                    {owner: tx-sender, content-url: content-url, access-control: access-control})
        (print "Content uploaded successfully")
        (ok "Content uploaded successfully")
    )
)

;; Update existing content owned by the user
(define-public (update-content (content-id uint) 
                               (content-url (string-ascii 256)) 
                               (access-control (list 100 principal)))
    (begin
        ;; Ensure the content exists and the user is the owner
        (match (only-owner content-id)
            success
            (begin
                (map-set user-content {content-id: content-id} 
                         {owner: tx-sender, content-url: content-url, access-control: access-control})
                (print "Content updated successfully")
                (ok "Content updated successfully")
            )
            err err
        )
    )
)

;; Retrieve the content URL if the user has access
(define-read-only (get-content (content-id uint))
    (begin
        ;; Ensure the content exists and the user has access
        (match (map-get? user-content {content-id: content-id})
            content
            (if (or (is-eq (tuple-get owner content) tx-sender) 
                    (contains tx-sender (tuple-get access-control content)))
                (ok (tuple-get content-url content))
                (err u1005) ;; Error code for "Access denied"
            )
            (err u1003) ;; Error code for "Content not found"
        )
    )
)

;; Grant access to a new user for specific content
(define-public (grant-access (content-id uint) (new-user principal))
    (begin
        ;; Ensure the content exists and the user is the owner
        (match (only-owner content-id)
            success
            (match (map-get? user-content {content-id: content-id})
                content
                (let ((current-access (tuple-get access-control content)))
                    ;; Ensure the access list isn't full
                    (asserts! (< (len current-access) 100) (err u1006)) ;; Error code for "Access control list full"
                    (let ((updated-access-control (append current-access (list new-user))))
                        (map-set user-content {content-id: content-id} 
                            {owner: tx-sender, content-url: (tuple-get content-url content), 
                             access-control: updated-access-control})
                        (print "Access granted successfully")
                        (ok "Access granted successfully")
                    )
                )
                (err u1003) ;; Error code for "Content not found"
            )
            err err
        )
    )
)

;; ========== Tipping Mechanism ========== ;;
;; Allow users to tip content creators
(define-public (tip-content-creator (recipient principal) (content-id uint) (amount uint))
    (begin
        ;; Ensure the content exists
        (asserts! (content-exists? content-id) (err u1003)) ;; Error code for "Content not found"
        ;; Ensure the sender has enough balance
        (asserts! (>= (ft-get-balance platform-token tx-sender) amount) (err u1001)) ;; Error code for "Insufficient balance"
        ;; Transfer the tokens
        (try! (ft-transfer? platform-token amount tx-sender recipient))
        (print (concat "Tipped " (uint-to-string amount) " tokens to " (principal-to-string recipient)))
        (ok amount)
    )
)

;; ========== Subscription Mechanism ========== ;;
(define-data-var subscriptions (map {subscriber: principal, content-id: uint} uint))

;; Subscribe to content by paying tokens
(define-public (subscribe (content-id uint) (amount uint))
    (begin
        ;; Ensure the content exists
        (asserts! (content-exists? content-id) (err u1003)) ;; Error code for "Content not found"
        ;; Ensure the sender has enough balance
        (asserts! (>= (ft-get-balance platform-token tx-sender) amount) (err u1001)) ;; Error code for "Insufficient balance"
        ;; Transfer the tokens to the content owner
        (match (map-get? user-content {content-id: content-id})
            content
            (begin
                (try! (ft-transfer? platform-token amount tx-sender (tuple-get owner content)))
                ;; Record the subscription
                (map-insert subscriptions {subscriber: tx-sender, content-id: content-id} amount)
                (print (concat "Subscribed to content ID " (uint-to-string content-id) " with " (uint-to-string amount) " tokens"))
                (ok amount)
            )
            (err u1007) ;; Error code for "Unable to retrieve content owner"
        )
    )
)

;; Check if a user is subscribed to specific content
(define-read-only (is-subscribed (user principal) (content-id uint))
    (is-some (map-get? subscriptions {subscriber: user, content-id: content-id}))
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
                (err u1000) ;; Error code for "Unauthorized action"
            )
            (err u1003) ;; Error code for "Content not found"
        )
    )
)

;; Retrieve proposal details
(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals proposal-id)
)

;; Get the current proposal counter
(define-read-only (get-proposal-counter)
    (var-get proposal-counter)
)
