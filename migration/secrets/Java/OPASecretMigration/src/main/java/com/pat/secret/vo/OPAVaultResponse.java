package com.pat.secret.vo;

import java.util.List;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

/**
 * Object to carry response payload from OPA
 * @author rajeshkumar
 *
 */

@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonIgnoreProperties(ignoreUnknown = true)
public class OPAVaultResponse{
	
	@JsonProperty("newObjectname")
	private String newObjectName;
	
	@JsonProperty("id")
	private String newObjectId;
	
	@JsonProperty("parent_folder_id")
	private String parentFolderId;
	
	@JsonProperty("description")
	private String secretDescription;
	
	@JsonProperty("created_at")
	private String createdat;
	
	@JsonProperty("created_by")
	private String createdby;
	
	@JsonProperty("updated_at")
	private String updatedat;
	
	@JsonProperty("updated_by")
	private String updatedby;
	
	@JsonProperty("path")
	private List<SecretPath> secretPath;

	@JsonProperty("name")
	public String getNewObjectName() {
		return newObjectName;
	}

	@JsonProperty("name")
	public void setNewObjectName(String newObjectName) {
		this.newObjectName = newObjectName;
	}

	@JsonProperty("id")
	public String getNewObjectId() {
		return newObjectId;
	}

	@JsonProperty("id")
	public void setNewObjectId(String secretID) {
		this.newObjectId = secretID;
	}

	@JsonProperty("parent_folder_id")
	public String getParentFolderId() {
		return parentFolderId;
	}

	@JsonProperty("parent_folder_id")
	public void setParentFolderId(String parentFolderId) {
		this.parentFolderId = parentFolderId;
	}

	@JsonProperty("description")
	public String getSecretDescription() {
		return secretDescription;
	}

	@JsonProperty("description")
	public void setSecretDescription(String secretDescription) {
		this.secretDescription = secretDescription;
	}
	
	@JsonProperty("created_at")
	public String getCreatedat() {
		return createdat;
	}

	@JsonProperty("created_at")
	public void setCreatedat(String createdat) {
		this.createdat = createdat;
	}

	@JsonProperty("created_by")
	public String getCreatedby() {
		return createdby;
	}

	@JsonProperty("created_by")
	public void setCreatedby(String createdby) {
		this.createdby = createdby;
	}

	@JsonProperty("updated_at")
	public String getUpdatedat() {
		return updatedat;
	}

	@JsonProperty("updated_at")
	public void setUpdatedat(String updatedat) {
		this.updatedat = updatedat;
	}

	@JsonProperty("updated_by")
	public String getUpdatedby() {
		return updatedby;
	}

	@JsonProperty("updated_by")
	public void setUpdatedby(String updatedby) {
		this.updatedby = updatedby;
	}
	
	@JsonProperty("path")
	public List<SecretPath> getSecretPath() {
		return secretPath;
	}

	@JsonProperty("path")
	public void setSecretPath(List<SecretPath> secretPath) {
		this.secretPath = secretPath;
	}

	@Override
	public String toString() {
		return "OPAVaultResponse [newObjectname=" + newObjectName + ", newObjectId=" + newObjectId + ", parentFolderId="
				+ parentFolderId + ", secretDescription=" + secretDescription + ", createdat=" + createdat
				+ ", createdby=" + createdby + ", updatedat=" + updatedat + ", updatedby=" + updatedby + ", secretPath="
				+ secretPath + "]";
	}
	
	

}
