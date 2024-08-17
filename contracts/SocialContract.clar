;; ========== User Content Smart Contract ========== ;;
;; This contract manages user-generated content on the blockchain.
;; Each piece of content is associated with a unique content ID and an owner.

(define-data-var user-content (map {content-id: uint} 
                                  {owner: principal, 
                                   content-url: (string-ascii 256), 
                                   access-control: (list 100 principal)}))

;; ========== Helper Functions ========== ;;
;; Checks if content with the given content ID exists
(define-private (content-exists? (content-id uint))
    (is-some (map-get? user-content {content-id: content-id}))
)

;; Ensures that only the owner of the content can modify it
(define-private (only-owner (content-id uint))
    (begin
        (match (map-get? user-content {content-id: content-id})
            content
            (if (is-eq (tuple-get owner content) tx-sender)
                (ok true)
                (err u1000) ;; Error code for "You are not the owner of this content."
            )
            (err u1001) ;; Error code for "Content not found."
        )
    )
)

;; ========== Public Functions ========== ;;
;; Uploads new content to the blockchain
(define-public (upload-content (content-id uint) 
                               (content-url (string-ascii 256)) 
                               (access-control (list 100 principal)))
    (begin
        (if (not (content-exists? content-id))
            (begin
                (map-insert user-content {content-id: content-id} 
                            {owner: tx-sender, 
                             content-url: content-url, 
                             access-control: access-control})
                (print "Content uploaded successfully")
                (ok "Content uploaded successfully")
            )
            (err u1002) ;; Error code for "Content ID already exists."
        )
    )
)

;; Updates existing content owned by the user
(define-public (update-content (content-id uint) 
                               (content-url (string-ascii 256)) 
                               (access-control (list 100 principal)))
    (begin
        (match (only-owner content-id)
            success
            (begin
                (map-set user-content {content-id: content-id} 
                         {owner: tx-sender, 
                          content-url: content-url, 
                          access-control: access-control})
                (print "Content updated successfully")
                (ok "Content updated successfully")
            )
            err err
        )
    )
)

;; Retrieves the content URL if the user has access
(define-read-only (get-content (content-id uint))
    (begin
        (match (map-get? user-content {content-id: content-id})
            content
            (if (or (is-eq (tuple-get owner content) tx-sender) 
                    (contains tx-sender (tuple-get access-control content)))
                (ok (tuple-get content-url content))
                (err u1003) ;; Error code for "You do not have access to this content."
            )
            (err u1001) ;; Error code for "Content not found."
        )
    )
)

;; Grants access to a new user for specific content
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
                                {owner: tx-sender, 
                                 content-url: (tuple-get content-url content), 
                                 access-control: updated-access-control})
                            (print "Access granted successfully")
                            (ok "Access granted successfully")
                        )
                        (err u1004) ;; Error code for "Access control list is full."
                    )
                )
                (err u1001) ;; Error code for "Content not found."
            )
            err err
        )
    )
)
