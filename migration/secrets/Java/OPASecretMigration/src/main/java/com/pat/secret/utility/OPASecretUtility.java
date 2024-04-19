package com.pat.secret.utility;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import com.pat.secret.vo.Hashicorp;

/**
 * Utility class with mulriple function to read properties from property file,
 * assemble endpoint URL
 * 
 * @author rajeshkumar
 *
 */
@Component
public class OPASecretUtility {

	// Logger
	private static final Logger LOGGER = LoggerFactory.getLogger(OPASecretUtility.class);

	private static RegisterProperties regProps;

	@Autowired
	private void setRegister(RegisterProperties regProps) {
		OPASecretUtility.regProps = regProps;
	}

	public OPASecretUtility() {

	}

	/**
	 * Request body for Token API
	 * 
	 * @return
	 */
	public String getAPITokenRequestBody() throws Exception {
		String requestBody = "";
		String svcKeyID = regProps.getOktapam().getClientID();
		String svcKeySecret = regProps.getOktapam().getClientSecret();
		LOGGER.debug("getAPITokenRequestBody svcKeyID ---> " + svcKeyID);
		// LOGGER.debug("svcKeySecret ---> " + svcKeySecret);
		requestBody = "{ \"key_id\": \"" + svcKeyID + "\", \"key_secret\": \"" + svcKeySecret + "\"}";
		return requestBody;
	}

	/**
	 * Token API Endpoint URL
	 * 
	 * @return
	 */
	public String getTokenAPIEndpoint() throws Exception {
		String apiEndpoint = regProps.getOktapam().getTokenendpoint();
		LOGGER.debug("getTokenAPIEndpoint apiEndpoint ---> " + apiEndpoint);
		String endpointURL = getAPIEndpoint(apiEndpoint);
		return endpointURL;
	}

	/**
	 * Team JWKS API Endpoint URL
	 * 
	 * @return
	 */
	public String getJWKSAPIEndpoint() throws Exception {
		String apiEndpoint = regProps.getOktapam().getJwksEndpoint();
		LOGGER.debug("getJWKSAPIEndpoint apiEndpoint ---> " + apiEndpoint);
		String endpointURL = getAPIEndpoint(apiEndpoint);
		return endpointURL;
	}

	/**
	 * Create Secret API Endpoint URL
	 * 
	 * @return
	 */
	public String getCreateSecretAPIEndpoint() throws Exception {
		String apiEndpoint = "/resource_groups/" + regProps.getOktapam().getResourceGroupId() + "/projects/"
				+ regProps.getOktapam().getProjectId() + regProps.getOktapam().getCreateSecretEndpoint();
		LOGGER.debug("getCreateSecretAPIEndpoint apiEndpoint ---> " + apiEndpoint);
		String endpointURL = getAPIEndpoint(apiEndpoint);
		return endpointURL;
	}

	/**
	 * Create Folder API Endpoint URL
	 * 
	 * @return
	 */
	public String getCreateFolderAPIEndpoint() throws Exception {
		String apiEndpoint = "/resource_groups/" + regProps.getOktapam().getResourceGroupId() + "/projects/"
				+ regProps.getOktapam().getProjectId() + regProps.getOktapam().getCreateFolderEndpoint();
		LOGGER.debug("getCreateFolderAPIEndpoint apiEndpoint ---> " + apiEndpoint);
		String endpointURL = getAPIEndpoint(apiEndpoint);
		return endpointURL;
	}

	/**
	 * Get API End Points URL
	 * 
	 * @param apiEndpoint
	 * @return
	 */
	private String getAPIEndpoint(String apiEndpoint) throws Exception {
		String hostURL = regProps.getOktapam().getHost();
		LOGGER.debug("getAPIEndpoint hostURL ---> " + hostURL);
		String endpointURI = regProps.getOktapam().getApiuri();
		LOGGER.debug("getAPIEndpoint endpointURI ---> " + endpointURI);
		String endpointURL = hostURL + endpointURI + apiEndpoint;
		LOGGER.debug("getAPIEndpoint endpointURL ---> " + endpointURL);
		return endpointURL;
	}

	/**
	 * Getting Hashicorp Environment details
	 * 
	 * @return
	 */
	public Hashicorp getHashicorpEnvironmentDetails() throws Exception {
		LOGGER.debug("Getting Hashicorp Environment Variables.");
		Hashicorp hashicorp = new Hashicorp();
		hashicorp = regProps.getHashicorp();
		LOGGER.debug("Hashicorp Environment host:port >>> " + hashicorp.getHost() + ":" + hashicorp.getPort());
		return hashicorp;
	}

}
