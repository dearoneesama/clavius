(Unit even$2
  [(VarDecl n$3 int) (VarDecl result$4 bool) (VarDecl $t1 bool)]
  [(Assume 1
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var n$3))
       (BinOp <= (Var n$3) (Int 9007199254740992))))
   (Assume 2 (BinOp >= (Var n$3) (Int 0)))
   (Block body
     [(Branch (BinOp == (Var n$3) (Int 0)) [(Assign result$4 (Bool true)) (Exit body)] [])
      (Check 1 (BinOp > (Var n$3) (Int 0)))
      (Check 2
        (BinOp or
          (BinOp and (BinOp <= (Int 0) (Var n$3)) (BinOp < (Var n$3) (Var n$3)))
          (BinOp and
            (BinOp == (Var n$3) (Var n$3))
            (BinOp and (BinOp <= (Int 0) (Int 1)) (BinOp < (Int 0) (Int 1))))))
      (Havoc $t1)
      (Assign result$4 (Var $t1))
      (Exit body)
      (Check 3 (Bool false))])])
(Unit odd$1
  [(VarDecl n$5 int) (VarDecl result$6 bool) (VarDecl $t1 int) (VarDecl $t2 bool)]
  [(Assume 3
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var n$5))
       (BinOp <= (Var n$5) (Int 9007199254740992))))
   (Assign $t1 (Var n$5))
   (Assume 4 (BinOp > (Var n$5) (Int 0)))
   (Block body
     [(Check 4
        (BinOp and
          (BinOp <= (Int -9007199254740992) (BinOp - (Var n$5) (Int 1)))
          (BinOp <= (BinOp - (Var n$5) (Int 1)) (Int 9007199254740992))))
      (Assign n$5 (BinOp - (Var n$5) (Int 1)))
      (Check 5 (BinOp >= (Var n$5) (Int 0)))
      (Check 6
        (BinOp or
          (BinOp and (BinOp <= (Int 0) (Var $t1)) (BinOp < (Var n$5) (Var $t1)))
          (BinOp and
            (BinOp == (Var n$5) (Var $t1))
            (BinOp and (BinOp <= (Int 0) (Int 0)) (BinOp < (Int 1) (Int 0))))))
      (Havoc $t2)
      (Assign result$6 (Not (Var $t2)))
      (Exit body)
      (Check 7 (Bool false))])])
(Unit fib$7
  [(VarDecl n$8 int) (VarDecl result$9 int) (VarDecl $t1 int) (VarDecl $t2 int)]
  [(Assume 5
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var n$8))
       (BinOp <= (Var n$8) (Int 9007199254740992))))
   (Assume 6 (BinOp >= (Var n$8) (Int 0)))
   (Block body
     [(Branch (BinOp < (Var n$8) (Int 2)) [(Assign result$9 (Var n$8)) (Exit body)] [])
      (Check 8
        (BinOp and
          (BinOp <= (Int -9007199254740992) (BinOp - (Var n$8) (Int 1)))
          (BinOp <= (BinOp - (Var n$8) (Int 1)) (Int 9007199254740992))))
      (Check 9 (BinOp >= (BinOp - (Var n$8) (Int 1)) (Int 0)))
      (Check 10
        (BinOp and (BinOp <= (Int 0) (Var n$8)) (BinOp < (BinOp - (Var n$8) (Int 1)) (Var n$8))))
      (Havoc $t1)
      (Assume 7
        (BinOp and
          (BinOp <= (Int -9007199254740992) (Var $t1))
          (BinOp <= (Var $t1) (Int 9007199254740992))))
      (Check 11
        (BinOp and
          (BinOp <= (Int -9007199254740992) (BinOp - (Var n$8) (Int 2)))
          (BinOp <= (BinOp - (Var n$8) (Int 2)) (Int 9007199254740992))))
      (Check 12 (BinOp >= (BinOp - (Var n$8) (Int 2)) (Int 0)))
      (Check 13
        (BinOp and (BinOp <= (Int 0) (Var n$8)) (BinOp < (BinOp - (Var n$8) (Int 2)) (Var n$8))))
      (Havoc $t2)
      (Assume 8
        (BinOp and
          (BinOp <= (Int -9007199254740992) (Var $t2))
          (BinOp <= (Var $t2) (Int 9007199254740992))))
      (Check 14
        (BinOp and
          (BinOp <= (Int -9007199254740992) (BinOp + (Var $t1) (Var $t2)))
          (BinOp <= (BinOp + (Var $t1) (Var $t2)) (Int 9007199254740992))))
      (Assign result$9 (BinOp + (Var $t1) (Var $t2)))
      (Exit body)
      (Check 15 (Bool false))])])
(Unit check$10
  [(VarDecl n$11 int) (VarDecl result$12 bool) (VarDecl $t1 bool)]
  [(Assume 9
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var n$11))
       (BinOp <= (Var n$11) (Int 9007199254740992))))
   (Assume 10 (BinOp >= (Var n$11) (Int 0)))
   (Block body
     [(Check 16 (BinOp >= (Var n$11) (Int 0)))
      (Havoc $t1)
      (Assign result$12 (Var $t1))
      (Exit body)
      (Check 17 (Bool false))])])
(Unit main$1
  [(VarDecl $t1 bool) (VarDecl x$13 bool)]
  [(Check 18 (BinOp >= (Int 4) (Int 0))) (Havoc $t1) (Assign x$13 (Var $t1))])

(obligation 1 :kind pre :node 26 :clause 36)
(obligation 2 :kind decrease :node 26 :clause 39)
(obligation 3 :kind missing_return :node 29)
(obligation 4 :kind range :node 47)
(obligation 5 :kind pre :node 51 :clause 8)
(obligation 6 :kind decrease :node 51 :clause 11)
(obligation 7 :kind missing_return :node 55)
(obligation 8 :kind range :node 80)
(obligation 9 :kind pre :node 81 :clause 62)
(obligation 10 :kind decrease :node 81 :clause 64)
(obligation 11 :kind range :node 85)
(obligation 12 :kind pre :node 86 :clause 62)
(obligation 13 :kind decrease :node 86 :clause 64)
(obligation 14 :kind range :node 87)
(obligation 15 :kind missing_return :node 90)
(obligation 16 :kind pre :node 104 :clause 8)
(obligation 17 :kind missing_return :node 107)
(obligation 18 :kind pre :node 111 :clause 97)

(assumption 1 :kind trusted :node 15 :decl 29)
(assumption 2 :kind trusted :node 8 :decl 29)
(assumption 3 :kind trusted :node 43 :decl 55)
(assumption 4 :kind trusted :node 36 :decl 55)
(assumption 5 :kind trusted :node 68 :decl 90)
(assumption 6 :kind trusted :node 62 :decl 90)
(assumption 7 :kind type_fact :node 81)
(assumption 8 :kind type_fact :node 86)
(assumption 9 :kind trusted :node 101 :decl 107)
(assumption 10 :kind trusted :node 97 :decl 107)
