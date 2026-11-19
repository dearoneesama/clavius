(Unit f$1
  [(VarDecl a$2 int) (VarDecl b$3 int) (VarDecl result$4 int)]
  [(Assume 1
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var a$2))
       (BinOp <= (Var a$2) (Int 9007199254740992))))
   (Assume 2
     (BinOp and
       (BinOp <= (Int -9007199254740992) (Var b$3))
       (BinOp <= (Var b$3) (Int 9007199254740992))))
   (Assume 3 (BinOp > (Var b$3) (Int 0)))
   (Block body
     [(Check 1 (BinOp != (Var b$3) (Int 0)))
      (Check 2 (BinOp != (Var b$3) (Int 0)))
      (Check 3
        (BinOp and
          (BinOp <=
            (Int -9007199254740992)
            (BinOp -
              (Var a$2)
              (Ite
                (BinOp and
                  (BinOp < (Var b$3) (Int 0))
                  (BinOp != (BinOp mod (Var a$2) (Var b$3)) (Int 0)))
                (BinOp + (BinOp mod (Var a$2) (Var b$3)) (Var b$3))
                (BinOp mod (Var a$2) (Var b$3)))))
          (BinOp <=
            (BinOp -
              (Var a$2)
              (Ite
                (BinOp and
                  (BinOp < (Var b$3) (Int 0))
                  (BinOp != (BinOp mod (Var a$2) (Var b$3)) (Int 0)))
                (BinOp + (BinOp mod (Var a$2) (Var b$3)) (Var b$3))
                (BinOp mod (Var a$2) (Var b$3))))
            (Int 9007199254740992))))
      (Check 4
        (BinOp and
          (BinOp <=
            (Int -9007199254740992)
            (BinOp +
              (Ite
                (BinOp and
                  (BinOp < (Var b$3) (Int 0))
                  (BinOp != (BinOp mod (Var a$2) (Var b$3)) (Int 0)))
                (BinOp - (BinOp div (Var a$2) (Var b$3)) (Int 1))
                (BinOp div (Var a$2) (Var b$3)))
              (Ite
                (BinOp and
                  (BinOp < (Var b$3) (Int 0))
                  (BinOp != (BinOp mod (Var a$2) (Var b$3)) (Int 0)))
                (BinOp + (BinOp mod (Var a$2) (Var b$3)) (Var b$3))
                (BinOp mod (Var a$2) (Var b$3)))))
          (BinOp <=
            (BinOp +
              (Ite
                (BinOp and
                  (BinOp < (Var b$3) (Int 0))
                  (BinOp != (BinOp mod (Var a$2) (Var b$3)) (Int 0)))
                (BinOp - (BinOp div (Var a$2) (Var b$3)) (Int 1))
                (BinOp div (Var a$2) (Var b$3)))
              (Ite
                (BinOp and
                  (BinOp < (Var b$3) (Int 0))
                  (BinOp != (BinOp mod (Var a$2) (Var b$3)) (Int 0)))
                (BinOp + (BinOp mod (Var a$2) (Var b$3)) (Var b$3))
                (BinOp mod (Var a$2) (Var b$3))))
            (Int 9007199254740992))))
      (Assign result$4
        (BinOp +
          (Ite
            (BinOp and
              (BinOp < (Var b$3) (Int 0))
              (BinOp != (BinOp mod (Var a$2) (Var b$3)) (Int 0)))
            (BinOp - (BinOp div (Var a$2) (Var b$3)) (Int 1))
            (BinOp div (Var a$2) (Var b$3)))
          (Ite
            (BinOp and
              (BinOp < (Var b$3) (Int 0))
              (BinOp != (BinOp mod (Var a$2) (Var b$3)) (Int 0)))
            (BinOp + (BinOp mod (Var a$2) (Var b$3)) (Var b$3))
            (BinOp mod (Var a$2) (Var b$3)))))
      (Check 5
        (BinOp ==
          (Var result$4)
          (BinOp +
            (Ite
              (BinOp and
                (BinOp < (Var b$3) (Int 0))
                (BinOp != (BinOp mod (Var a$2) (Var b$3)) (Int 0)))
              (BinOp - (BinOp div (Var a$2) (Var b$3)) (Int 1))
              (BinOp div (Var a$2) (Var b$3)))
            (Ite
              (BinOp and
                (BinOp < (Var b$3) (Int 0))
                (BinOp != (BinOp mod (Var a$2) (Var b$3)) (Int 0)))
              (BinOp + (BinOp mod (Var a$2) (Var b$3)) (Var b$3))
              (BinOp mod (Var a$2) (Var b$3))))))
      (Exit body)
      (Check 6 (Bool false))])])

(obligation 1 :kind div_zero :node 35)
(obligation 2 :kind div_zero :node 38)
(obligation 3 :kind mod_range :node 38)
(obligation 4 :kind range :node 39)
(obligation 5 :kind post :node 40 :clause 23)
(obligation 6 :kind missing_return :node 42)

(assumption 1 :kind trusted :node 27 :decl 42)
(assumption 2 :kind trusted :node 28 :decl 42)
(assumption 3 :kind trusted :node 9 :decl 42)
