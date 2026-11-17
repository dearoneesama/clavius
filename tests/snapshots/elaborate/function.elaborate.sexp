(Unit f$1
  [(VarDecl n$2 int) (VarDecl on$3 bool) (VarDecl result$4 int) (VarDecl $t1 int)]
  [(Assume 1
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var n$2))
       (BinOp <= (Var n$2) (Int 9007199254740992))))
   (Assign $t1 (Var n$2))
   (Assume 2 (BinOp > (Var n$2) (Int 0)))
   (Block body
     [(Branch
        (Var on$3)
        [(Check 1
           (BinOp and
             (BinOp <= (Int -9007199254740992) (BinOp + (Var n$2) (Int 1)))
             (BinOp <= (BinOp + (Var n$2) (Int 1)) (Int 9007199254740992))))
         (Assign n$2 (BinOp + (Var n$2) (Int 1)))
         (Assign result$4 (Var n$2))
         (Check 2 (BinOp >= (Var result$4) (Var $t1)))
         (Exit body)]
        [(Branch
           (BinOp > (Var n$2) (Int 10))
           [(Check 3
              (BinOp and
                (BinOp <= (Int -9007199254740992) (BinOp * (Var n$2) (Int 2)))
                (BinOp <= (BinOp * (Var n$2) (Int 2)) (Int 9007199254740992))))
            (Assign result$4 (BinOp * (Var n$2) (Int 2)))
            (Check 4 (BinOp >= (Var result$4) (Var $t1)))
            (Exit body)]
           [(Branch
              (BinOp == (Var n$2) (Int 1))
              [(Assign result$4 (Int 1)) (Check 5 (BinOp >= (Var result$4) (Var $t1))) (Exit body)]
              [])])])
      (Assign result$4 (Var n$2))
      (Check 6 (BinOp >= (Var result$4) (Var $t1)))
      (Exit body)
      (Check 7 (Bool false))])])
(Unit g$5
  [(VarDecl n$6 int) (VarDecl $t1 int)]
  [(Assume 3
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var n$6))
       (BinOp <= (Var n$6) (Int 9007199254740992))))
   (Assign $t1 (Var n$6))
   (Assume 4 (BinOp > (Var n$6) (Int 0)))
   (Block body
     [(Branch (BinOp > (Var n$6) (Int 5)) [(Check 8 (BinOp > (Var $t1) (Int 0))) (Exit body)] [])
      (Check 9
        (BinOp and
          (BinOp <= (Int -9007199254740992) (BinOp - (Var n$6) (Int 1)))
          (BinOp <= (BinOp - (Var n$6) (Int 1)) (Int 9007199254740992))))
      (Assign n$6 (BinOp - (Var n$6) (Int 1)))
      (Check 10 (BinOp > (Var $t1) (Int 0)))])])
(Unit h$7
  [(VarDecl n$8 int) (VarDecl result$9 int) (VarDecl $t1 int) (VarDecl $t2 int) (VarDecl $t3 int)]
  [(Assume 5
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var n$8))
       (BinOp <= (Var n$8) (Int 9007199254740992))))
   (Assume 6 (BinOp and (BinOp > (Var n$8) (Int 0)) (BinOp < (Var n$8) (Int 10))))
   (Block body
     [(Branch
        (BinOp > (Var n$8) (Int 5))
        [(Check 11 (BinOp > (Var n$8) (Int 0)))
         (Havoc $t1)
         (Assume 7
           (BinOp and
             (BinOp <= (Int -9007199254740992) (Var $t1))
             (BinOp <= (Var $t1) (Int 9007199254740992))))
         (Assume 8 (BinOp >= (Var $t1) (Var n$8)))
         (Assign result$9 (Var $t1))
         (Check 12 (BinOp >= (Var result$9) (Var n$8)))
         (Exit body)]
        [])
      (Check 13 (BinOp > (Var n$8) (Int 0)))
      (Havoc $t2)
      (Assume 9
        (BinOp and
          (BinOp <= (Int -9007199254740992) (Var $t2))
          (BinOp <= (Var $t2) (Int 9007199254740992))))
      (Assume 10 (BinOp >= (Var $t2) (Var n$8)))
      (Check 14 (BinOp > (Var n$8) (Int 0)))
      (Havoc $t3)
      (Assume 11
        (BinOp and
          (BinOp <= (Int -9007199254740992) (Var $t3))
          (BinOp <= (Var $t3) (Int 9007199254740992))))
      (Assume 12 (BinOp >= (Var $t3) (Var n$8)))
      (Check 15
        (BinOp and
          (BinOp <= (Int -9007199254740992) (BinOp + (Var $t2) (Var $t3)))
          (BinOp <= (BinOp + (Var $t2) (Var $t3)) (Int 9007199254740992))))
      (Assign result$9 (BinOp + (Var $t2) (Var $t3)))
      (Check 16 (BinOp >= (Var result$9) (Var n$8)))
      (Exit body)
      (Check 17 (Bool false))])])

(obligation 1 :kind range :node 23)
(obligation 2 :kind post :node 26 :clause 13)
(obligation 3 :kind range :node 34)
(obligation 4 :kind post :node 35 :clause 13)
(obligation 5 :kind post :node 42 :clause 13)
(obligation 6 :kind post :node 50 :clause 13)
(obligation 7 :kind missing_return :node 52)
(obligation 8 :kind post :node 70 :clause 64)
(obligation 9 :kind range :node 77)
(obligation 10 :kind post :node 80 :clause 64)
(obligation 11 :kind pre :node 107 :clause 9)
(obligation 12 :kind post :node 108 :clause 96)
(obligation 13 :kind pre :node 115 :clause 9)
(obligation 14 :kind pre :node 119 :clause 9)
(obligation 15 :kind range :node 120)
(obligation 16 :kind post :node 121 :clause 96)
(obligation 17 :kind missing_return :node 123)

(assumption 1 :kind trusted :node 17 :decl 52)
(assumption 2 :kind trusted :node 9 :decl 52)
(assumption 3 :kind trusted :node 66 :decl 80)
(assumption 4 :kind trusted :node 60 :decl 80)
(assumption 5 :kind trusted :node 100 :decl 123)
(assumption 6 :kind trusted :node 92 :decl 123)
(assumption 7 :kind type_fact :node 107)
(assumption 8 :kind callee_post :node 107)
(assumption 9 :kind type_fact :node 115)
(assumption 10 :kind callee_post :node 115)
(assumption 11 :kind type_fact :node 119)
(assumption 12 :kind callee_post :node 119)
