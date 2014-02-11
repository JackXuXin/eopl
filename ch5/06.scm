(load-relative "../libs/init.scm")
(load-relative "./base/test.scm")
(load-relative "./base/letrec-cases.scm")

;; add list expression into interpreter, based on 5.10, ref 3.10
;; add list->pairs to transfer a normal list into pairs
;; see new stuff

 ;;;;;;;;;;;;;;;;; grammatical specification ;;;;;;;;;;;;;;;;
(define the-lexical-spec
  '((whitespace (whitespace) skip)
    (comment ("%" (arbno (not #\newline))) skip)
    (identifier
     (letter (arbno (or letter digit "_" "-" "?")))
     symbol)
    (number (digit (arbno digit)) number)
    (number ("-" digit (arbno digit)) number)
    ))

(define the-grammar
  '((program (expression) a-program)

    (expression (number) const-exp)
    (expression
     ("-" "(" expression "," expression ")")
     diff-exp)

    (expression
     ("zero?" "(" expression ")")
     zero?-exp)

    (expression
     ("if" expression "then" expression "else" expression)
     if-exp)

    (expression (identifier) var-exp)

    (expression
     ("let" identifier "=" expression "in" expression)
     let-exp)

    (expression
     ("proc" "(" identifier ")" expression)
     proc-exp)

    (expression
     ("(" expression expression ")")
     call-exp)

    (expression
     ("letrec"
      identifier "(" identifier ")" "=" expression
      "in" expression)
     letrec-exp)

    (expression ("cons" "(" expression "," expression ")") cons-exp)
    (expression ("car" "(" expression ")") car-exp)
    (expression ("cdr" "(" expression ")") cdr-exp)
    (expression ("emptylist") emptylist-exp)
    (expression ("null?" "(" expression ")") null?-exp)
    ;;new stuff
    (expression ("list" "(" (separated-list expression ",") ")" ) list-exp)

    ))

  ;;;;;;;;;;;;;;;; sllgen boilerplate ;;;;;;;;;;;;;;;;

(sllgen:make-define-datatypes the-lexical-spec the-grammar)

(define show-the-datatypes
  (lambda () (sllgen:list-define-datatypes the-lexical-spec the-grammar)))

(define scan&parse
  (sllgen:make-string-parser the-lexical-spec the-grammar))

(define-datatype expval expval?
  (num-val
   (value number?))
  (bool-val
   (boolean boolean?))
  (proc-val
   (proc proc?))
  (pair-val
   (car expval?)
   (cdr expval?))
  (emptylist-val))

;;; extractors:

(define expval->num
  (lambda (v)
    (cases expval v
           (num-val (num) num)
           (else (expval-extractor-error 'num v)))))

(define expval->bool
  (lambda (v)
    (cases expval v
           (bool-val (bool) bool)
           (else (expval-extractor-error 'bool v)))))

(define expval->proc
  (lambda (v)
    (cases expval v
           (proc-val (proc) proc)
           (else (expval-extractor-error 'proc v)))))

(define expval->pair
  (lambda (v)
    (cases expval v
           (pair-val (car cdr)
                     (cons car cdr))
           (else (expval-extractor-error 'pair v)))))

(define expval-car
  (lambda (v)
    (cases expval v
           (pair-val (car cdr) car)
           (else (expval-extractor-error 'car v)))))

(define expval-cdr
  (lambda (v)
    (cases expval v
           (pair-val (car cdr) cdr)
           (else (expval-extractor-error 'cdr v)))))

(define expval-null?
  (lambda (v)
    (cases expval v
           (emptylist-val () (bool-val #t))
           (else (bool-val #f)))))

(define expval-extractor-error
  (lambda (variant value)
    (error 'expval-extractors "Looking for a ~s, found ~s"
           variant value)))

;;;;;;;;;;;;;;;; continuations ;;;;;;;;;;;;;;;;
(define identifier? symbol?)

(define-datatype continuation continuation?
  (end-cont)
  (zero1-cont
   (saved-cont continuation?))
  (let-exp-cont
   (var identifier?)
   (body expression?)
   (saved-env environment?)
   (saved-cont continuation?))
  (if-test-cont
   (exp2 expression?)
   (exp3 expression?)
   (saved-env environment?)
   (saved-cont continuation?))
  (diff1-cont
   (exp2 expression?)
   (saved-env environment?)
   (saved-cont continuation?))
  (diff2-cont
   (val1 expval?)
   (saved-cont continuation?))
  (rator-cont
   (rand expression?)
   (saved-env environment?)
   (saved-cont continuation?))
  (rand-cont
   (val1 expval?)
   (saved-cont continuation?))
  (cons-cont
   (exp2 expression?)
   (saved-env environment?)
   (saved-cont continuation?))
  (cons-cont2
   (val1 expval?)
   (saved-cont continuation?))
  (car-cont
   (saved-cont continuation?))
  (cdr-cont
   (saved-cont continuation?))
  (null?-cont
   (saved-cont continuation?))
  ;;new stuff
  (list-cont
   (args (list-of expression?))
   (saved-env environment?)
   (saved-cont continuation?))
  (list-cont-else
   (args (list-of expression?))
   (prev-args list?)
   (saved-env environment?)
   (saved-cont continuation?)))

;;;;;;;;;;;;;;;; procedures ;;;;;;;;;;;;;;;;
(define-datatype proc proc?
  (procedure
   (bvar symbol?)
   (body expression?)
   (env environment?)))

;;;;;;;;;;;;;;;; environment structures ;;;;;;;;;;;;;;;;
(define-datatype environment environment?
  (empty-env)
  (extend-env
   (bvar symbol?)
   (bval expval?)
   (saved-env environment?))
  (extend-env-rec
   (p-name symbol?)
   (b-var symbol?)
   (p-body expression?)
   (saved-env environment?)))

(define init-env
  (lambda ()
    (extend-env
     'i (num-val 1)
     (extend-env
      'v (num-val 5)
      (extend-env
       'x (num-val 10)
       (empty-env))))))

;;;;;;;;;;;;;;;; environment constructors and observers ;;;;;;;;;;;;;;;;
(define apply-env
  (lambda (env search-sym)
    (cases environment env
           (empty-env ()
                      (error 'apply-env "No binding for ~s" search-sym))
           (extend-env (var val saved-env)
                       (if (eqv? search-sym var)
                           val
                           (apply-env saved-env search-sym)))
           (extend-env-rec (p-name b-var p-body saved-env)
                           (if (eqv? search-sym p-name)
                               (proc-val (procedure b-var p-body env))
                               (apply-env saved-env search-sym))))))


;; value-of-program : Program -> FinalAnswer
(define value-of-program
  (lambda (pgm)
    (cases program pgm
           (a-program (exp1)
                      (value-of/k exp1 (init-env) (end-cont))))))

;;new stuff
(define list->pairs
  (lambda (L)
    (if (null? L)
	  (emptylist-val)
	  (pair-val (car L)
		    (list->pairs (cdr L))))))

;; value-of/k : Exp * Env * Cont -> FinalAnswer
(define value-of/k
  (lambda (exp env cont)
    (cases expression exp
           (const-exp (num) (apply-cont cont (num-val num)))
           (var-exp (var) (apply-cont cont (apply-env env var)))
           (proc-exp (var body)
                     (apply-cont cont
                                 (proc-val (procedure var body env))))
           (letrec-exp (p-name b-var p-body letrec-body)
                       (value-of/k letrec-body
                                   (extend-env-rec p-name b-var p-body env)
                                   cont))
           (zero?-exp (exp1)
                      (value-of/k exp1 env
                                  (zero1-cont cont)))
           (let-exp (var exp1 body)
                    (value-of/k exp1 env
                                (let-exp-cont var body env cont)))
           (if-exp (exp1 exp2 exp3)
                   (value-of/k exp1 env
                               (if-test-cont exp2 exp3 env cont)))
           (diff-exp (exp1 exp2)
                     (value-of/k exp1 env
                                 (diff1-cont exp2 env cont)))
           (call-exp (rator rand)
                     (value-of/k rator env
                                 (rator-cont rand env cont)))
           (emptylist-exp ()
                          (apply-cont cont (emptylist-val)))
           (cons-exp (exp1 exp2)
                     (value-of/k exp1 env
                                 (cons-cont exp2 env cont)))
           (car-exp (exp)
                    (value-of/k exp env (car-cont cont)))
           (cdr-exp (exp)
                    (value-of/k exp env (cdr-cont cont)))

           (null?-exp (exp)
                      (value-of/k exp env (null?-cont cont)))

	   ;;new stuff
	   (list-exp (args)
		     (if (null? args)
			 (apply-cont cont (emptylist-val))
			 (value-of/k (car args)
				     env
				     (list-cont (cdr args) env cont))))
           )))

;; apply-cont : Cont * ExpVal -> FinalAnswer
(define apply-cont
  (lambda (cont val)
    (cases continuation cont
           (end-cont ()
                     (begin
                       (printf
                        "End of computation.~%")
                       val))
           (zero1-cont (saved-cont)
                       (apply-cont saved-cont
                                   (bool-val
                                    (zero? (expval->num val)))))
           (let-exp-cont (var body saved-env saved-cont)
                         (value-of/k body
                                     (extend-env var val saved-env) saved-cont))
           (if-test-cont (exp2 exp3 saved-env saved-cont)
                         (if (expval->bool val)
                             (value-of/k exp2 saved-env saved-cont)
                             (value-of/k exp3 saved-env saved-cont)))
           (diff1-cont (exp2 saved-env saved-cont)
                       (value-of/k exp2
                                   saved-env (diff2-cont val saved-cont)))
           (diff2-cont (val1 saved-cont)
                       (let ((num1 (expval->num val1))
                             (num2 (expval->num val)))
                         (apply-cont saved-cont
                                     (num-val (- num1 num2)))))
           (rator-cont (rand saved-env saved-cont)
                       (value-of/k rand saved-env
                                   (rand-cont val saved-cont)))
           (rand-cont (val1 saved-cont)
                      (let ((proc (expval->proc val1)))
                        (apply-procedure/k proc val saved-cont)))

	   (cons-cont (exp2 saved-env saved-cont)
                      (value-of/k exp2 saved-env
                                  (cons-cont2 val saved-cont)))
           (cons-cont2 (val1 saved-cont)
                       (apply-cont saved-cont
                                   (pair-val val1 (pair-val val (emptylist-val)))))
           (car-cont (saved-cont)
                     (apply-cont saved-cont
                                 (expval-car val)))
           (cdr-cont (saved-cont)
                     (apply-cont saved-cont
                                 (expval-cdr val)))

           (null?-cont (saved-cont)
                       (apply-cont saved-cont
                                   (expval-null? val)))

	   ;;new stuff
	   (list-cont (args saved-env saved-cont)
		      (if (null? args)
			  (apply-cont saved-cont
				      (pair-val val (emptylist-val)))
			  (value-of/k (car args)
				      saved-env
				      (list-cont-else (cdr args)
						      (list val)
						      saved-env saved-cont))))
	   (list-cont-else (args prev-args saved-env saved-cont)
		      (if (null? args)
			  (apply-cont saved-cont
				      (list->pairs (append prev-args (list val))))
			  (value-of/k (car args)
				      saved-env
				      (list-cont-else
				       (cdr args)
				       (append prev-args (list val))
				       saved-env
				       saved-cont))))
           )))

;; apply-procedure/k : Proc * ExpVal * Cont -> FinalAnswer
(define apply-procedure/k
  (lambda (proc1 arg cont)
    (cases proc proc1
           (procedure (var body saved-env)
                      (value-of/k body
                                  (extend-env var arg saved-env)
                                  cont)))))

(define run
  (lambda (string)
    (value-of-program (scan&parse string))))

(add-test! '(test-0 "emptylist" ()))
(add-test! '(test-1 "null? (emptylist)" #t))
(add-test! '(test-2 "null? (cons (1, 2))" #f))
(add-test! '(test-3 "car (cons (1, 2))" 1))
(add-test! '(test-4 "cdr (cons (1, 2))" (2)))
(add-test! '(test-5 "cons (1, 2)" (1 2)))
(add-test! '(test-6 "car (cdr (cons (1, 2)))" 2))
(add-test! '(test-7 "let x = 4
                        in cons(x,
                         cons(cons(-(x,1),
                          emptylist),
                            emptylist))"
		    (4 ((3 ()) ()))))


(add-test! '(list-0 "1" 1))
(add-test! '(list-1 "list()" ()))
(add-test! '(list-2 "list(1)" (1)))
(add-test! '(list-3 "list(1, 2)" (1 2)))
(add-test! '(list-4 "list(1, 2, 3, 4)" (1 2 3 4)))

(add-test! '(list-5 "cdr(list(1, 2))" (2)))
(add-test! '(list-6 "car (cdr(list(1, 2)))" 2))
(add-test! '(list-7 "car(list(1, 2, 3))" 1))
(add-test! '(list-8 "let x = 4
                    in list(x, -(x,1), -(x,2))"
		    (4 3 2)))

(run-all)
