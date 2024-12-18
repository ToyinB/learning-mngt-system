;; Learning Management System Smart Contract

(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u1))
(define-constant ERR-NOT-FOUND (err u2))
(define-constant ERR-ALREADY-EXISTS (err u3))
(define-constant ERR-INVALID-INPUT (err u4))
(define-constant ERR-COURSE-FULL (err u5))
(define-constant ERR-ALREADY-ENROLLED (err u6))
(define-constant ERR-COURSE-NOT-STARTED (err u7))
(define-constant ERR-COURSE-COMPLETED (err u8))

;; Define data maps for storing information
(define-map users 
    principal 
    {
        name: (string-utf8 50),
        email: (string-utf8 100),
        role: (string-ascii 10),
        created-at: uint
    }
)

(define-map courses 
    uint 
    {
        id: uint,
        title: (string-utf8 100),
        description: (string-utf8 500),
        instructor: principal,
        max-capacity: uint,
        current-enrollments: uint,
        start-date: uint,
        end-date: uint,
        is-active: bool
    }
)

(define-map enrollments 
    {course-id: uint, student: principal} 
    {
        enrollment-date: uint,
        progress: uint,
        completed: bool
    }
)

(define-map course-materials
    {course-id: uint, material-id: uint}
    {
        title: (string-utf8 100),
        content-url: (string-utf8 500),
        material-type: (string-ascii 20)
    }
)

;; Variable to keep track of the last course ID
(define-data-var last-course-id uint u0)

;; Variable to keep track of the last material ID for each course
(define-map last-material-id uint uint)

;; Helper function to validate string length
(define-private (validate-string-length (input (string-utf8 500)) (max-length uint))
    (<= (len input) max-length)
)

;; Enhanced helper function to validate ASCII string
(define-private (validate-ascii-string (input (string-ascii 20)) (max-length uint))
    (and 
        (> (len input) u0)
        (<= (len input) max-length)
    )
)

;; Enhanced helper function to validate role with a more robust check
(define-private (validate-role (role (string-ascii 10)))
    (let ((cleaned-role (default-to "" (as-max-len? role u10))))
        (or 
            (is-eq cleaned-role "student") 
            (is-eq cleaned-role "instructor") 
            (is-eq cleaned-role "admin")
        )
    )
)

;; Enhanced helper function to validate material type with a more robust check
(define-private (validate-material-type (material-type (string-ascii 20)))
    (let ((cleaned-type (default-to "" (as-max-len? material-type u20))))
        (or 
            (is-eq cleaned-type "video")
            (is-eq cleaned-type "pdf")
            (is-eq cleaned-type "text")
            (is-eq cleaned-type "quiz")
        )
    )
)

;; Safe course deactivation with strict input validation
(define-private (safe-course-deactivate 
    (course-id uint)
    (course-title (string-utf8 100))
    (course-description (string-utf8 500))
    (course-instructor principal)
    (course-max-capacity uint)
    (course-current-enrollments uint)
    (course-start-date uint)
    (course-end-date uint)
    (course-is-active bool)
)
    (map-set courses course-id {
        id: course-id,
        title: course-title,
        description: course-description,
        instructor: course-instructor,
        max-capacity: course-max-capacity,
        current-enrollments: course-current-enrollments,
        start-date: course-start-date,
        end-date: course-end-date,
        is-active: false
    })
)

;; User Registration
(define-public (register-user
    (name (string-utf8 50))
    (email (string-utf8 100))
    (role (string-ascii 10))
)
    (begin
        ;; Enhanced input validation
        (asserts! (and 
            (> (len name) u0) 
            (validate-string-length name u50)
        ) ERR-INVALID-INPUT)
        
        (asserts! (and 
            (> (len email) u0) 
            (validate-string-length email u100)
        ) ERR-INVALID-INPUT)
        
        ;; Additional safety checks for ASCII strings
        (asserts! (is-some (as-max-len? role u10)) ERR-INVALID-INPUT)
        
        (asserts! (validate-role role) ERR-INVALID-INPUT)
        
        ;; Check if user already exists
        (asserts! (is-none (map-get? users tx-sender)) ERR-ALREADY-EXISTS)
        
        ;; Register user with validated inputs
        (map-set users tx-sender {
            name: name,
            email: email,
            role: (unwrap-panic (as-max-len? role u10)),
            created-at: block-height
        })
        
        (ok true)
    )
)

;; Create Course (Only by Instructors or Admins)
(define-public (create-course
    (title (string-utf8 100))
    (description (string-utf8 500))
    (max-capacity uint)
    (start-date uint)
    (end-date uint)
)
    (let (
        (course-id (+ (var-get last-course-id) u1))
        (user-info (unwrap! (map-get? users tx-sender) ERR-UNAUTHORIZED))
    )
        ;; Enhanced input validation
        (asserts! (and 
            (> (len title) u0) 
            (validate-string-length title u100)
        ) ERR-INVALID-INPUT)
        
        (asserts! (and 
            (> (len description) u0) 
            (validate-string-length description u500)
        ) ERR-INVALID-INPUT)
        
        (asserts! (> max-capacity u0) ERR-INVALID-INPUT)
        (asserts! (< start-date end-date) ERR-INVALID-INPUT)
        
        ;; Ensure only instructors or admins can create courses
        (asserts! 
            (or 
                (is-eq (get role user-info) "instructor")
                (is-eq (get role user-info) "admin")
            ) 
            ERR-UNAUTHORIZED
        )
        
        ;; Create course
        (map-set courses course-id {
            id: course-id,
            title: title,
            description: description,
            instructor: tx-sender,
            max-capacity: max-capacity,
            current-enrollments: u0,
            start-date: start-date,
            end-date: end-date,
            is-active: true
        })
        
        ;; Update last-course-id
        (var-set last-course-id course-id)
        
        ;; Initialize last-material-id for this course
        (map-set last-material-id course-id u0)
        
        (ok course-id)
    )
)

;; Enroll in Course
(define-public (enroll-in-course (course-id uint))
    (let (
        (course (unwrap! (map-get? courses course-id) ERR-NOT-FOUND))
        (user-info (unwrap! (map-get? users tx-sender) ERR-UNAUTHORIZED))
    )
        ;; Validate enrollment conditions
        (asserts! (get is-active course) ERR-COURSE-NOT-STARTED)
        (asserts! (< (get current-enrollments course) (get max-capacity course)) ERR-COURSE-FULL)
        (asserts! 
            (is-none 
                (map-get? enrollments {course-id: course-id, student: tx-sender})
            ) 
            ERR-ALREADY-ENROLLED
        )
        
        ;; Update course enrollments
        (map-set courses course-id 
            (merge course {
                current-enrollments: (+ (get current-enrollments course) u1)
            })
        )
        
        ;; Create enrollment record
        (map-set enrollments 
            {course-id: course-id, student: tx-sender}
            {
                enrollment-date: block-height,
                progress: u0,
                completed: false
            }
        )
        
        (ok true)
    )
)

;; Add Course Material
(define-public (add-course-material
    (course-id uint)
    (title (string-utf8 100))
    (content-url (string-utf8 500))
    (material-type (string-ascii 20))
)
    (let (
        (course (unwrap! (map-get? courses course-id) ERR-NOT-FOUND))
        (user-info (unwrap! (map-get? users tx-sender) ERR-UNAUTHORIZED))
        (material-id (+ (default-to u0 (map-get? last-material-id course-id)) u1))
    )
        ;; Enhanced input validation
        (asserts! (and 
            (> (len title) u0) 
            (validate-string-length title u100)
        ) ERR-INVALID-INPUT)
        
        (asserts! (and 
            (> (len content-url) u0) 
            (validate-string-length content-url u500)
        ) ERR-INVALID-INPUT)
        
        ;; Additional safety checks for ASCII strings
        (asserts! (is-some (as-max-len? material-type u20)) ERR-INVALID-INPUT)
        
        (asserts! (validate-material-type material-type) ERR-INVALID-INPUT)
        
        ;; Validate creator is course instructor
        (asserts! (is-eq tx-sender (get instructor course)) ERR-UNAUTHORIZED)
        
        ;; Add course material with validated inputs
        (map-set course-materials 
            {course-id: course-id, material-id: material-id}
            {
                title: title,
                content-url: content-url,
                material-type: (unwrap-panic (as-max-len? material-type u20))
            }
        )
        
        ;; Update last-material-id for this course
        (map-set last-material-id course-id material-id)
        
        (ok material-id)
    )
)

;; Update Course Progress
(define-public (update-course-progress 
    (course-id uint)
    (progress uint)
)
    (let (
        (enrollment (unwrap! 
            (map-get? enrollments {course-id: course-id, student: tx-sender}) 
            ERR-NOT-FOUND
        ))
        (course (unwrap! (map-get? courses course-id) ERR-NOT-FOUND))
    )
        ;; Validate progress update
        (asserts! (get is-active course) ERR-COURSE-NOT-STARTED)
        (asserts! (<= progress u100) ERR-INVALID-INPUT)
        
        ;; Update enrollment progress
        (map-set enrollments 
            {course-id: course-id, student: tx-sender}
            (merge enrollment {
                progress: progress,
                completed: (>= progress u100)
            })
        )
        
        (ok true)
    )
)

;; Get Helper Functions
(define-read-only (get-user-info (user principal))
    (map-get? users user)
)

(define-read-only (get-course-details (course-id uint))
    (map-get? courses course-id)
)

(define-read-only (get-enrollment-details (course-id uint) (student principal))
    (map-get? enrollments {course-id: course-id, student: student})
)

(define-read-only (get-course-material (course-id uint) (material-id uint))
    (map-get? course-materials {course-id: course-id, material-id: material-id})
)

(define-read-only (get-course-materials-count (course-id uint))
    (default-to u0 (map-get? last-material-id course-id))
)

;; Get last course ID
(define-read-only (get-last-course-id)
    (var-get last-course-id)
)

