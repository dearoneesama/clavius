(Unit f$1
  [(VarDecl n$2 int)
   (VarDecl result$3 int)
   (VarDecl i$4 int)
   (VarDecl s$5 int)
   (VarDecl $t1 int)
   (VarDecl $t2 int)
   (VarDecl j$6 int)
   (VarDecl $t3 int)
   (VarDecl k$7 int)]
  [(Assume 1
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var n$2))
       (BinOp <= (Var n$2) (Int 9007199254740992))))
   (Assume 2 (BinOp and (BinOp >= (Var n$2) (Int 0)) (BinOp < (Var n$2) (Int 100))))
   (Block body
     [(Assign i$4 (Int 0))
      (Assign s$5 (Int 0))
      (Check 1 (BinOp <= (Var i$4) (Var n$2)))
      (Block loop$1
        [(Havoc i$4)
         (Assume 3
           (BinOp and
             (BinOp <= (Int -9007199254740992) (Var i$4))
             (BinOp <= (Var i$4) (Int 9007199254740992))))
         (Assume 4 (BinOp <= (Var i$4) (Var n$2)))
         (Assign $t1 (BinOp - (Var n$2) (Var i$4)))
         (Branch
           (BinOp < (Var i$4) (Var n$2))
           [(Branch (BinOp > (Var s$5) (Int 50)) [(Exit loop$1)] [])
            (Check 2
              (BinOp and
                (BinOp <= (Int -9007199254740992) (BinOp + (Var i$4) (Int 1)))
                (BinOp <= (BinOp + (Var i$4) (Int 1)) (Int 9007199254740992))))
            (Assign i$4 (BinOp + (Var i$4) (Int 1)))
            (Check 3 (BinOp <= (Var i$4) (Var n$2)))
            (Check 4
              (BinOp and
                (BinOp <= (Int 0) (Var $t1))
                (BinOp < (BinOp - (Var n$2) (Var i$4)) (Var $t1))))
            (Assume 5 (Bool false))]
           [])])
      (Block loop$2
        [(Havoc i$4)
         (Assume 6
           (BinOp and
             (BinOp <= (Int -9007199254740992) (Var i$4))
             (BinOp <= (Var i$4) (Int 9007199254740992))))
         (Assign $t2 (BinOp - (Var n$2) (Var i$4)))
         (Check 5
           (BinOp and
             (BinOp <= (Int -9007199254740992) (BinOp + (Var i$4) (Int 1)))
             (BinOp <= (BinOp + (Var i$4) (Int 1)) (Int 9007199254740992))))
         (Assign j$6 (BinOp + (Var i$4) (Int 1)))
         (Assign i$4 (Var j$6))
         (Branch
           (BinOp >= (Var j$6) (Var n$2))
           []
           [(Check 6
              (BinOp and
                (BinOp <= (Int 0) (Var $t2))
                (BinOp < (BinOp - (Var n$2) (Var i$4)) (Var $t2))))
            (Assume 7 (Bool false))])])
      (Assign $t3 (Var n$2))
      (Branch
        (BinOp >= (Var $t3) (Int 1))
        [(Check 7
           (BinOp and
             (BinOp <= (Int -9007199254740992) (BinOp + (Int 1) (Int -2)))
             (BinOp <= (BinOp + (Int 1) (Int -2)) (Int 9007199254740992))))
         (Assign k$7 (Var $t3))
         (Check 8
           (BinOp and
             (BinOp and
               (BinOp <= (BinOp + (Int 1) (Int -2)) (Var k$7))
               (BinOp <= (Var k$7) (Var $t3)))
             (BinOp == (BinOp mod (BinOp - (Var k$7) (Var $t3)) (Int 2)) (Int 0))))
         (Check 9 (BinOp >= (Var s$5) (Int 0)))
         (Block loop$3
           [(Havoc k$7)
            (Assume 8
              (BinOp and
                (BinOp and
                  (BinOp <= (BinOp + (Int 1) (Int -2)) (Var k$7))
                  (BinOp <= (Var k$7) (Var $t3)))
                (BinOp == (BinOp mod (BinOp - (Var k$7) (Var $t3)) (Int 2)) (Int 0))))
            (Havoc s$5)
            (Assume 9
              (BinOp and
                (BinOp <= (Int -9007199254740992) (Var s$5))
                (BinOp <= (Var s$5) (Int 9007199254740992))))
            (Assume 10 (BinOp >= (Var s$5) (Int 0)))
            (Branch
              (BinOp >= (Var k$7) (Int 1))
              [(Check 10
                 (BinOp and
                   (BinOp <= (Int -9007199254740992) (BinOp + (Var s$5) (Var k$7)))
                   (BinOp <= (BinOp + (Var s$5) (Var k$7)) (Int 9007199254740992))))
               (Assign s$5 (BinOp + (Var s$5) (Var k$7)))
               (Assign k$7 (BinOp + (Var k$7) (Int -2)))
               (Check 11
                 (BinOp and
                   (BinOp and
                     (BinOp <= (BinOp + (Int 1) (Int -2)) (Var k$7))
                     (BinOp <= (Var k$7) (Var $t3)))
                   (BinOp == (BinOp mod (BinOp - (Var k$7) (Var $t3)) (Int 2)) (Int 0))))
               (Check 12 (BinOp >= (Var s$5) (Int 0)))
               (Assume 11 (Bool false))]
              [])])]
        [])
      (Assign result$3 (Var i$4))
      (Check 13 (BinOp == (Var result$3) (Var n$2)))
      (Exit body)
      (Check 14 (Bool false))])])
(Unit g$8
  [(VarDecl n$9 int) (VarDecl d$10 int) (VarDecl $t1 int) (VarDecl $t2 int) (VarDecl k$11 int)]
  [(Assume 12
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var n$9))
       (BinOp <= (Var n$9) (Int 9007199254740992))))
   (Assume 13
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var d$10))
       (BinOp <= (Var d$10) (Int 9007199254740992))))
   (Assume 14
     (BinOp and
       (BinOp and
         (BinOp and (BinOp >= (Var n$9) (Int 0)) (BinOp < (Var n$9) (Int 100)))
         (BinOp >= (Var d$10) (Int -3)))
       (BinOp <= (Var d$10) (Int 3))))
   (Block body
     [(Assign $t1 (Var n$9))
      (Assign $t2 (Var d$10))
      (Check 15 (BinOp != (Var $t2) (Int 0)))
      (Branch
        (BinOp or
          (BinOp and (BinOp < (Int 0) (Var $t2)) (BinOp <= (Int 1) (Var $t1)))
          (BinOp and (BinOp < (Var $t2) (Int 0)) (BinOp >= (Int 1) (Var $t1))))
        [(Check 16
           (BinOp and
             (BinOp <= (Int -9007199254740992) (BinOp + (Var $t1) (Var $t2)))
             (BinOp <= (BinOp + (Var $t1) (Var $t2)) (Int 9007199254740992))))
         (Assign k$11 (Int 1))
         (Check 17
           (BinOp or
             (BinOp and
               (BinOp < (Int 0) (Var $t2))
               (BinOp and
                 (BinOp <= (Int 1) (Var k$11))
                 (BinOp <= (Var k$11) (BinOp + (Var $t1) (Var $t2)))))
             (BinOp and
               (BinOp < (Var $t2) (Int 0))
               (BinOp and
                 (BinOp <= (BinOp + (Var $t1) (Var $t2)) (Var k$11))
                 (BinOp <= (Var k$11) (Int 1))))))
         (Block loop$1
           [(Havoc k$11)
            (Assume 15
              (BinOp or
                (BinOp and
                  (BinOp < (Int 0) (Var $t2))
                  (BinOp and
                    (BinOp <= (Int 1) (Var k$11))
                    (BinOp <= (Var k$11) (BinOp + (Var $t1) (Var $t2)))))
                (BinOp and
                  (BinOp < (Var $t2) (Int 0))
                  (BinOp and
                    (BinOp <= (BinOp + (Var $t1) (Var $t2)) (Var k$11))
                    (BinOp <= (Var k$11) (Int 1))))))
            (Branch
              (BinOp or
                (BinOp and (BinOp < (Int 0) (Var $t2)) (BinOp <= (Var k$11) (Var $t1)))
                (BinOp and (BinOp < (Var $t2) (Int 0)) (BinOp >= (Var k$11) (Var $t1))))
              [(Assign k$11 (BinOp + (Var k$11) (Var $t2)))
               (Check 18
                 (BinOp or
                   (BinOp and
                     (BinOp < (Int 0) (Var $t2))
                     (BinOp and
                       (BinOp <= (Int 1) (Var k$11))
                       (BinOp <= (Var k$11) (BinOp + (Var $t1) (Var $t2)))))
                   (BinOp and
                     (BinOp < (Var $t2) (Int 0))
                     (BinOp and
                       (BinOp <= (BinOp + (Var $t1) (Var $t2)) (Var k$11))
                       (BinOp <= (Var k$11) (Int 1))))))
               (Assume 16 (Bool false))]
              [])])]
        [])])])

(obligation 1 :kind invariant_entry :node 49 :clause 28)
(obligation 2 :kind range :node 46)
(obligation 3 :kind invariant_preserved :node 49 :clause 28)
(obligation 4 :kind decrease :node 49 :clause 32)
(obligation 5 :kind range :node 56)
(obligation 6 :kind decrease :node 66 :clause 53)
(obligation 7 :kind for_bound :node 82)
(obligation 8 :kind invariant_entry :node 82)
(obligation 9 :kind invariant_entry :node 82 :clause 70)
(obligation 10 :kind range :node 79)
(obligation 11 :kind invariant_preserved :node 82)
(obligation 12 :kind invariant_preserved :node 82 :clause 70)
(obligation 13 :kind post :node 84 :clause 14)
(obligation 14 :kind missing_return :node 86)
(obligation 15 :kind for_step :node 117)
(obligation 16 :kind for_bound :node 117)
(obligation 17 :kind invariant_entry :node 117)
(obligation 18 :kind invariant_preserved :node 117)

(assumption 1 :kind trusted :node 18 :decl 86)
(assumption 2 :kind trusted :node 10 :decl 86)
(assumption 3 :kind type_fact :node 49)
(assumption 4 :kind invariant :node 28)
(assumption 5 :kind back_edge :node 49)
(assumption 6 :kind type_fact :node 66)
(assumption 7 :kind back_edge :node 66)
(assumption 8 :kind invariant :node 82)
(assumption 9 :kind type_fact :node 82)
(assumption 10 :kind invariant :node 70)
(assumption 11 :kind back_edge :node 82)
(assumption 12 :kind trusted :node 110 :decl 119)
(assumption 13 :kind trusted :node 111 :decl 119)
(assumption 14 :kind trusted :node 108 :decl 119)
(assumption 15 :kind invariant :node 117)
(assumption 16 :kind back_edge :node 117)
