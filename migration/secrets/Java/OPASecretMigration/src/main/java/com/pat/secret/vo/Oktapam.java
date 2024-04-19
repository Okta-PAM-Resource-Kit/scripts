package com.pat.secret.vo;

/**
 * Object to load OPA specific properties from property file
 * @author rajeshkumar
 *
 */

public class Oktapam {
	
	private String host;
	private String team;
	private String apiuri;
	private String clientID;
	private String clientSecret;
	private String tokenendpoint;
	private String jwksEndpoint;
	private String createSecretEndpoint;
	private String createFolderEndpoint;
	private String resourceGroupId;
	private String projectId;
	private String parentSecretFolderId;
	private String secretFolderDesc;
	
	public String getHost() {
		return host;
	}
	
	public void setHost(String host) {
		this.host = host;
	}
	
	public String getTeam() {
		return team;
	}
	
	public void setTeam(String team) {
		this.team = team;
	}
	
	public String getApiuri() {
		return apiuri;
	}
	
	public void setApiuri(String apiuri) {
		this.apiuri = apiuri;
	}
	
	public String getClientID() {
		return clientID;
	}
	
	public void setClientID(String clientID) {
		this.clientID = clientID;
	}
	
	public String getClientSecret() {
		return clientSecret;
	}
	
	public void setClientSecret(String clientSecret) {
		this.clientSecret = clientSecret;
	}
	
	public String getTokenendpoint() {
		return tokenendpoint;
	}
	
	public void setTokenendpoint(String tokenendpoint) {
		this.tokenendpoint = tokenendpoint;
	}

	public String getJwksEndpoint() {
		return jwksEndpoint;
	}

	public void setJwksEndpoint(String jwksEndpoint) {
		this.jwksEndpoint = jwksEndpoint;
	}
	
	public String getCreateSecretEndpoint() {
		return createSecretEndpoint;
	}

	public void setCreateSecretEndpoint(String createSecretEndpoint) {
		this.createSecretEndpoint = createSecretEndpoint;
	}

	public String getCreateFolderEndpoint() {
		return createFolderEndpoint;
	}

	public void setCreateFolderEndpoint(String createFolderEndpoint) {
		this.createFolderEndpoint = createFolderEndpoint;
	}
	
	public String getResourceGroupId() {
		return resourceGroupId;
	}

	public void setResourceGroupId(String resourceGroupId) {
		this.resourceGroupId = resourceGroupId;
	}

	public String getProjectId() {
		return projectId;
	}

	public void setProjectId(String projectId) {
		this.projectId = projectId;
	}

	public String getParentSecretFolderId() {
		return parentSecretFolderId;
	}

	public void setParentSecretFolderId(String parentSecretFolderId) {
		this.parentSecretFolderId = parentSecretFolderId;
	}

	public String getSecretFolderDesc() {
		return secretFolderDesc;
	}

	public void setSecretFolderDesc(String secretFolderDesc) {
		this.secretFolderDesc = secretFolderDesc;
	}

	@Override
	public String toString() {
		return "Oktapam [host=" + host + ", team=" + team + ", apiuri=" + apiuri + ", clientID=" + clientID
				+ ", clientSecret=" + clientSecret + ", tokenendpoint=" + tokenendpoint + ", jwksEndpoint="
				+ jwksEndpoint + ", createSecretEndpoint=" + createSecretEndpoint + ", createFolderEndpoint="
				+ createFolderEndpoint + ", resourceGroupId=" + resourceGroupId + ", projectId=" + projectId
				+ ", parentSecretFolderId=" + parentSecretFolderId + ", secretFolderDesc=" + secretFolderDesc + "]";
	}
	
}
