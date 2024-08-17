;; ========== Platform Token Creation ========== ;;
;; Define the platform token. This example uses a basic fungible token implementation.
(define-fungible-token platform-token 1000000) ;; Total supply of 1,000,000 tokens

;; Mint new tokens to a user. Typically, this would be restricted to certain roles.
(define-public (mint-tokens (recipient principal) (amount uint))
    (begin
        (try! (ft-mint? platform-token amount recipient))
        (print (concat "Minted " (uint-to-string amount) " tokens to " (principal-to-string recipient)))
        (ok amount)
    )
)

;; Allow a user to transfer tokens to another user.
(define-public (transfer-tokens (recipient principal) (amount uint))
    (begin
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
        (if (map-get? user-profiles tx-sender)
            (err "Profile already exists. Use update-profile instead.")
            (begin
                (map-insert user-profiles tx-sender 
                            {username: username, bio: bio, profile-pic-url: profile-pic-url})
                (print "Profile created successfully")
                (ok "Profile created successfully")
            )
        )
    )
)

;; Update an existing user profile
(define-public (update-profile (username (string-ascii 32)) 
                               (bio (optional (string-ascii 160))) 
                               (profile-pic-url (optional (string-ascii 256))))
    (begin
        (match (map-get? user-profiles tx-sender)
            profile
            (begin
                (map-set user-profiles tx-sender 
                         {username: username, bio: bio, profile-pic-url: profile-pic-url})
                (print "Profile updated successfully")
                (ok "Profile updated successfully")
            )
            (err "Profile does not exist. Create a profile first.")
        )
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
        (if (not (content-exists? content-id))
            (begin
                (map-insert user-content {content-id: content-id} 
                            {owner: tx-sender, content-url: content-url, access-control: access-control})
                (print "Content uploaded successfully")
                (ok "Content uploaded successfully")
            )
            (err "Content ID already exists.")
        )
    )
)

;; Update existing content owned by the user
(define-public (update-content (content-id uint) 
                               (content-url (string-ascii 256)) 
                               (access-control (list 100 principal)))
    (begin
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
        (match (map-get? user-content {content-id: content-id})
            content
            (if (or (is-eq (tuple-get owner content) tx-sender) 
                    (contains tx-sender (tuple-get access-control content)))
                (ok (tuple-get content-url content))
                (err "You do not have access to this content.")
            )
            (err "Content not found.")
        )
    )
)

;; Grant access to a new user for specific content
(define-public (grant-access (content-id uint) (new-user principal))
    (begin
        (match (only-owner content-id)
            success
            (match (map-get? user-content {content-id: content-id})
                content
                (let ((current-access (tuple-get access-control content)))
                    (if (< (len current-access) 100)
                        (let ((updated-access-control (append current-access (list new-user))))
                            (map-set user-content {content-id: content-id} 
                                {owner: tx-sender, content-url: (tuple-get content-url content), 
                                 access-control: updated-access-control})
                            (print "Access granted successfully")
                            (ok "Access granted successfully")
                        )
                        (err "Access control list is full.")
                    )
                )
                (err "Content not found.")
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
        (asserts! (content-exists? content-id) (err u2001)) ;; Error code for "Content not found."
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
        (asserts! (content-exists? content-id) (err u2001)) ;; Error code for "Content not found."
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
            (err u2002) ;; Error code for "Unable to retrieve content owner."
        )
    )
)

;; Check if a user is subscribed to specific content
(define-read-only (is-subscribed (user principal) (content-id uint))
    (is-some (map-get? subscriptions {subscriber: user, content-id: content-id}))
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
                (err "You are not the owner of this content.")
            )
            (err "Content not found.")
        )
    )
)
