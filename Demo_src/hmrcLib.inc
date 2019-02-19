
SCHEMA njm_demo310

TYPE t_hmrcOrganisations RECORD
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
	END RECORD

TYPE t_hmrcOrganisationsJSON RECORD
  	userId VARCHAR(30),
  	password VARCHAR(30),
  	userFullName VARCHAR(100),
  	emailAddress VARCHAR(200),
		organisationDetails RECORD
			name VARCHAR(20),
			address RECORD
				line1 VARCHAR(100),
				line2 VARCHAR(100),
				postcode VARCHAR(10)
			END RECORD
		END RECORD,
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
	END RECORD

TYPE t_hmrcAccessToken RECORD
		vrn VARCHAR(20),
		token VARCHAR(64), 
		refresh_token VARCHAR(64),
		token_endpoint VARCHAR(200),
		token_expires DATETIME YEAR TO SECOND
	END RECORD