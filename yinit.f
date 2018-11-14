      SUBROUTINE YINIT(Y,W,VL,IV,P,CENT,EINT,EVAL,EVECS,
     1                 IPROP,N,MXLAM,NPOTL,ISCRU,ISTART,
     2                 ESHIFT,R,RMLMDA,ZOUT,IREAD,IWRITE,
     3                 IPRINT)
C  Copyright (C) 2018 J. M. Hutson & C. R. Le Sueur
C  Distributed under the GNU General Public License, version 3
      IMPLICIT NONE
C  THIS SUBROUTINE INITIALISES THE Y MATRIX USED BY LOG-DERIVATIVE
C  PROPAGATORS.
C  STARTED TO BE WRITTEN BY CRLS ON 30-6-16
C
C  ON ENTRY:
C  Y      CONTAINS Y MATRIX FROM PREVIOUS PROPAGATION (IF ISTART=1)
C  VL,IV,P,CENT,EINT   } ARE USED TO EVALUATE THE W MATRIX
C  R,RMLMDA,MXLAM,NPOTL}
C  IPROP  INDICATES THE NUMERICAL VALUE OF THE CURRENT PROPAGATOR
C  ISCRU  CONTAINS THE STREAM NUMBER FOR THE SCRATCH FILE (0 IF NOT
C         USED)
C  ZOUT   INDICATES IF DIRECTION OF PROPAGATION IS OUTWARDS
C  IREAD  INDICATES WHETHER W MATRIX IS TO BE READ FROM ISCRU
C  IWRITE INDICATES WHETHER W MATRIX IS TO BE WRITTEN TO ISCRU
C  ISTART INDICATES WHETHER Y MATRIX NEEDS TO BE INITIALISED (ISTART=0)
C         OR NOT (ISTART=1)
C
C  ON EXIT:
C  W      CONTAINS THE W MATRIX
C  EVAL   CONTAINS ITS EIGENVALUES
C  EVECS  CONTAINS THE EIGENVECTORS OF THE W MATRIX
      DOUBLE PRECISION, INTENT(INOUT):: Y(N,N)
      DOUBLE PRECISION, INTENT(OUT):: W(N,N),EVAL(N),EVECS(N,N)

      DOUBLE PRECISION, INTENT(IN):: VL(1),P(1),ESHIFT,R,EINT(N),
     &                               RMLMDA,CENT(N)
      LOGICAL, INTENT(IN):: ZOUT,IREAD,IWRITE
      INTEGER, INTENT(IN):: ISTART,
     &                      IPROP,N,ISCRU,IV(1),MXLAM,
     &                      NPOTL,IPRINT
C
C  COMMON BLOCK FOR CONTROL OF PROPAGATION BOUNDARY CONDITIONS
      COMMON /BCCTRL/ BCYCMN,BCYCMX,BCYOMN,BCYOMX,ADIAMN,ADIAMX,
     1                WKBMN,WKBMX
      LOGICAL ADIAMN,ADIAMX,WKBMN,WKBMX
      DOUBLE PRECISION BCYCMN,BCYCMX,BCYOMN,BCYOMX

C  INTERNAL VARIABLES
      INTEGER I,J,NOPEN,IFAIL
      DOUBLE PRECISION DIR,ERED,WREF,ETMP,CVL,OVL,YVAL,EWAV
      DOUBLE PRECISION, ALLOCATABLE:: TEMP(:,:),DIAG(:)

      DOUBLE PRECISION, PARAMETER:: ZERTOL=1D-10

      LOGICAL USE_DG,USECVL,AD_BAS

C  USE_DG MEANS USE DIAGONAL ELEMENTS
      USE_DG=(ZOUT .AND. .NOT.ADIAMN) .OR. (.NOT.ZOUT .AND. .NOT.ADIAMX)

C  AD_BAS MEANS PROPAGATOR WORKS IN (QUASI-) ADIABATIC BASIS
      AD_BAS=(IPROP.EQ.1 .OR. IPROP.EQ.7)

      DIR=1.D0
      IF (.NOT.ZOUT) DIR=-1.D0

      ETMP=ESHIFT
      EWAV=0.D0
C  TO REPRODUCE PREVIOUS RESULTS, BECAUSE DIAGONALISER IS QUITE
C  SENSITIVE TO DIAGONAL SHIFTS
      IF (IPROP.EQ.1) THEN
        EWAV=ETMP
        ETMP=0.D0
      ENDIF

      IF (.NOT.IREAD) THEN
C  CALCULATE THE W MATRIX AT ZERO ENERGY AND THEN SHIFT DIAGONAL
C  ELEMENTS BY ETMP LATER
        ALLOCATE(DIAG(N))
        W=0.D0
        CALL WAVMAT(W,N,R,P,VL,IV,EWAV,EINT,CENT,RMLMDA,DIAG,
     1              MXLAM,NPOTL,IPRINT)
C  IPROP=1 USES -W RATHER THAN W
        IF (IPROP.EQ.1) W=-W

C  NEED EIGENVALUES IF USING THE ADIABATIC BASIS
C  NEED EIGENVECTORS IF TRANSFORMING BETWEEN PRIMITIVE AND ADIABATIC
C  BASES
        IF ((.NOT.USE_DG .AND. ISTART.EQ.0) .OR.
     1      (AD_BAS .AND. ISTART.EQ.1)) THEN
          CALL F02ABF(W,N,N,EVAL,EVECS,N,DIAG,IFAIL)
        ELSE
          EVECS=0.D0
          DO I=1,N
            EVECS(I,I)=1.D0
          ENDDO
        ENDIF
        DEALLOCATE (DIAG)
        IF (IWRITE) WRITE(ISCRU) W,EVAL
      ELSE
        READ(ISCRU) W,EVAL
      ENDIF

C  SET UP SOME INTERNAL VARIABLES
      USECVL=(ZOUT .AND. .NOT.WKBMN) .OR.
     1       (.NOT.ZOUT .AND. .NOT.WKBMX)
      IF (ZOUT) THEN
        CVL=BCYCMN
        OVL=BCYOMN
      ELSE
        CVL=BCYCMX
        OVL=BCYOMX
      ENDIF

C  SHIFT THE RELEVANT QUANTITY BY ETMP
      DO I=1,N
        IF (.NOT.AD_BAS) W(I,I)=W(I,I)-ETMP
        IF (.NOT.USE_DG) EVAL(I)=EVAL(I)-ETMP
      ENDDO

C  IF Y MATRIX DOESN'T NEED INITIALISING, THAT'S ALL
      IF (ISTART.EQ.1) THEN
        RETURN
      ENDIF

      Y=0.D0

      NOPEN=0
      DO I=1,N
C  CHOOSE THE CORRECT VALUES (EITHER DIAGONALS OF W OR EIGENVALUES) TO
C  PUT INTO THE Y MATRIX
        IF (USE_DG) THEN
          YVAL=W(I,I)
        ELSE
          YVAL=EVAL(I)
        ENDIF
        IF (IPROP.EQ.1) YVAL=-YVAL
        IF (YVAL.GT.0D0) THEN
          IF (USECVL) THEN
            Y(I,I)=DIR*CVL
          ELSE
            Y(I,I)=DIR*SQRT(ABS(YVAL))
          ENDIF
        ELSE
          Y(I,I)=DIR*OVL
          IF (ABS(YVAL).GT.ZERTOL) NOPEN=NOPEN+1
        ENDIF
      ENDDO
C
      IF (NOPEN.GT.0) THEN
        IF (ZOUT) THEN
          WRITE(6,601) NOPEN,'RMIN'
        ELSEIF (IPRINT.GE.8) THEN
          WRITE(6,601) NOPEN,'RMAX'
  601     FORMAT(' **** WARNING:',I5,' OPEN CHANNELS DETECTED AT ',A4)
        ENDIF
      ENDIF
C
      IF (USE_DG .EQV. AD_BAS) THEN
C  IF PROPAGATOR WORKS IN THE FREE BASIS, NEED TO ROTATE Y FROM
C  LOCAL BASIS INTO FREE BASIS (Y_PROP=EVECS*Y_LOCAL*EVECS^T)
C
C  ALSO IF PROPAGATOR WORKS IN LOCAL BASIS, NEED TO ROTATE Y
C  FROM FREE BASIS INTO LOCAL BASIS (Y_PROP=EVECS^T*Y_LOCAL*EVECS)
        ALLOCATE (TEMP(N,N))
        IF (.NOT.USE_DG) CALL TRNSP(EVECS,N)
C  (NOTE: IPROP=7 MAKES USE OF EVECS)
        CALL TRNSFM(EVECS,Y,TEMP,N,.FALSE.,.TRUE.)
        DEALLOCATE(TEMP)
      ENDIF

      IF (IPRINT.GE.20) THEN
        CALL MATPRN(6,Y,N,N,N,2,Y,' YINIT',1)
      ENDIF

      RETURN
      END
