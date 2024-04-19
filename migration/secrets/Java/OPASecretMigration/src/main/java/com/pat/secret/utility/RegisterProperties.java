package com.pat.secret.utility;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

import com.pat.secret.vo.Hashicorp;
import com.pat.secret.vo.Oktapam;

/**
 * Load property start with register and load into respective Objects
 * @author rajeshkumar
 *
 */

@Component
@ConfigurationProperties("register") // prefix app, find register.* values
public class RegisterProperties {

	private Oktapam oktapam = new Oktapam();
	private Hashicorp hashicorp = new Hashicorp();

	public Oktapam getOktapam() {
		return oktapam;
	}

	public void setOktapam(Oktapam oktapam) {
		this.oktapam = oktapam;
	}

	public Hashicorp getHashicorp() {
		return hashicorp;
	}

	public void setHashicorp(Hashicorp hashicorp) {
		this.hashicorp = hashicorp;
	}

	@Override
	public String toString() {
		return "RegisterProperties [oktapam=" + oktapam + ", hashicorp=" + hashicorp + "]";
	}

}
