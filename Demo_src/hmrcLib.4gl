IMPORT util

&include "hmrcLib.inc"

PUBLIC DEFINE m_db_err STRING
FUNCTION connectToDB()
	DEFINE l_dbName STRING

	LET l_dbName = fgl_getEnv("DBNAME")
	TRY
		CONNECT TO l_dbName
		RETURN TRUE
	CATCH
		LET m_db_err = SFMT( "Error for DB '%1':%2", l_dbName ,SQLERRMESSAGE )
		RETURN FALSE
	END TRY
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION errDisp( l_msg STRING )
	DEFINE l_rec RECORD
		code STRING,
		message STRING
	END RECORD
	CALL disp(l_msg)
	IF l_msg.subString(1,1) = "{" THEN
		CALL util.JSON.parse( l_msg, l_rec )
		CALL fgl_winMessage(l_rec.code, l_rec.message,"exclamation")
	ELSE
		CALL fgl_winMessage("Error", l_msg, "exclamation")
	END IF
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION errDisp2( l_msg STRING, l_url STRING, l_data STRING )
	LET l_data = l_data.trim()
	DISPLAY SFMT("%1) %2\n%3", CURRENT, l_msg, l_data)
	OPEN WINDOW err WITH FORM "ws_error"
	DISPLAY BY NAME l_msg, l_url, l_data
	MENU
		ON ACTION close EXIT MENU
		ON ACTION exit EXIT MENU
	END MENU
	CLOSE WINDOW err
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION processing( l_msg STRING )
	CALL disp( l_msg )
	MESSAGE SFMT("%1) %2", CURRENT, l_msg)
	CALL ui.Interface.refresh()
ENd FUNCTION
--------------------------------------------------------------------------------
FUNCTION disp( l_msg STRING )
	DISPLAY SFMT("%1) %2", CURRENT, l_msg)
ENd FUNCTION
--------------------------------------------------------------------------------
-- create the tables if they don't exist
FUNCTION chkTables()
	IF ARG_VAL(1) = "RESET" THEN
		TRY
			DROP TABLE hmrcAccessTokens
		CATCH
		END TRY
		TRY
			DROP TABLE hmrcOrganisations
		CATCH
		END TRY
	END IF

	TRY
		CREATE TABLE hmrcAccessTokens (
			vrn VARCHAR(20),
			token VARCHAR(64), 
			refresh_token VARCHAR(64),
			token_endpoint VARCHAR(200),
			token_expires DATETIME YEAR TO SECOND
		)
		DISPLAY  "Table hmrcAccessTokens created."
	CATCH
		DISPLAY "Table hmrcAccessTokens already exists"
	END TRY

	TRY
		CREATE TABLE hmrcOrganisations (
			userId VARCHAR(30),
			password VARCHAR(30),
			userFullName VARCHAR(100),
			emailAddress VARCHAR(200),
			org_name VARCHAR(20),
			org_address_line1 VARCHAR(100),
			org_address_line2 VARCHAR(100),
			org_address_pcode VARCHAR(10),
			saUtr VARCHAR(20),
			nino VARCHAR(20),
			mtdItId VARCHAR(25),
			mpRef VARCHAR(25),
			ctUtr VARCHAR(20),
			vrn VARCHAR(20),
			vatRegistrationDate DATE,
			lisaManagerReferenceNumber VARCHAR(20),
			secureElectronicTransferReferenceNumber VARCHAR(20),
			pensionSchemeAdministratorIdentifier VARCHAR(20),
			eoriNumber VARCHAR(20)
		)
		DISPLAY  "Table hmrcOrganisations created."
	CATCH
		DISPLAY "Table hmrcOrganisations already exists"
	END TRY
END FUNCTION
--------------------------------------------------------------------------------
FUNCTION updateTokenInDB( l_hmrcToken t_hmrcAccessToken)
	SELECT * FROM hmrcAccessTokens WHERE vrn = l_hmrcToken.vrn
	IF STATUS = NOTFOUND THEN
		INSERT INTO hmrcAccessTokens VALUES( l_hmrcToken.* )
		IF STATUS != 0 THEN
			LET m_db_err = "New Token insert failed:",STATUS,":",SQLERRMESSAGE
			RETURN FALSE
		END IF
	ELSE
		UPDATE hmrcAccessTokens SET hmrcAccessTokens.* = l_hmrcToken.* WHERE vrn = l_hmrcToken.vrn
		IF STATUS != 0 THEN
			LET m_db_err = "New Token update failed:",STATUS,":",SQLERRMESSAGE
			RETURN FALSE
		END IF
	END IF
	RETURN TRUE
ENd FUNCTION