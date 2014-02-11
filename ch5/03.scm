(load-relative "../libs/init.scm")
(load-relative "./base/test.scm")
(load-relative "./base/letrec-cases.scm")

;; add let2 for lang,
;; let2 is like a let expression, except it defines exactly two variables

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

    ;;new stuff
    (expression
     ("let2" identifier "," identifier "="
             expression "," expression
	     "in" expression)
     let2-exp)

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
   (proc proc?)))

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

(define expval-extractor-error
  (lambda (variant value)
    (error 'expval-extractors "Looking for a ~s, found ~s"
	   variant value)))

;;;;;;;;;;;;;;;; continuations ;;;;;;;;;;;;;;;;
(define identifier? symbol?)

;;new stuff
(define-datatype continuation continuation?
  (end-cont)
  (zero1-cont
   (saved-cont continuation?))
  (let-exp-cont
   (var identifier?)
   (body expression?)
   (saved-env environment?)
   (saved-cont continuation?))
  (let2-exp-cont
   (var1 identifier?)
   (var2 identifier?)
   (val2 expression?)
   (body expression?)
   (saved-env environment?)
   (saved-cont continuation?))
  (let2-exp-cont2
   (var2 identifier?)
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

	   ;;new stuff
	   (let2-exp (var1 var2 exp1 exp2 body)
		     (value-of/k exp1 env
				 (let2-exp-cont var1 var2 exp2 body env cont)))

	   (if-exp (exp1 exp2 exp3)
		   (value-of/k exp1 env
			       (if-test-cont exp2 exp3 env cont)))
	   (diff-exp (exp1 exp2)
		     (value-of/k exp1 env
				 (diff1-cont exp2 env cont)))
	   (call-exp (rator rand)
		     (value-of/k rator env
				 (rator-cont rand env cont)))
	   )))

;; apply-cont : Cont * ExpVal -> FinalAnswer
;; Page: 148
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
				     (extend-env var val saved-env)
				     saved-cont))

	   ;; new stuff
	   (let2-exp-cont (var1 var2 val2 body saved-env saved-cont)
			  (value-of/k val2
				      saved-env
				      (let2-exp-cont2 var2 body
						      (extend-env var1 val saved-env)
						      saved-cont)))

	   (let2-exp-cont2 (var2 body saved-env saved-cont)
			   (value-of/k body
				       (extend-env var2 val saved-env)
				       saved-cont))

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


(add-test! '(let2-test
	     "let2 x,y = 1, 2
                in -(x, y)"
	     -1))

(add-test! '(let2-test-cont
          "let2 x, y = -(1, 2), 10
          in -(x, -(x, y))"
           10))


(run-all)
