package com.pat.secret;

import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.ConfigurableApplicationContext;

import com.pat.secret.bo.OPASecretServicesBO;

@SpringBootApplication
public class OPASecretMigrationApplication implements CommandLineRunner {

	public static void main(String[] args) {
		ConfigurableApplicationContext context = SpringApplication.run(OPASecretMigrationApplication.class, args);
		context.close();
	}

	// access command line arguments
	public void run(String... args) throws Exception {

		try {
			OPASecretServicesBO opaSecretServicesBO = new OPASecretServicesBO();
			opaSecretServicesBO.migrateHashicorpSecret();
		} catch (Exception e) {
			e.printStackTrace();
		}

	}

	
}
