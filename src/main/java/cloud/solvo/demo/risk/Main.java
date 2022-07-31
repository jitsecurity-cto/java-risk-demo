package cloud.solvo.demo.risk;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

import org.apache.commons.io.IOUtils;
import org.apache.commons.lang3.StringUtils;
import org.eclipse.jetty.server.Request;
import org.eclipse.jetty.server.Server;
import org.eclipse.jetty.server.handler.AbstractHandler;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import software.amazon.awssdk.auth.credentials.EnvironmentVariableCredentialsProvider;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;

public class Main extends AbstractHandler {
	private static final Logger logger = LoggerFactory.getLogger(Main.class);

	@Override
	public void handle(String target, Request baseRequest, HttpServletRequest request, HttpServletResponse response)
			throws IOException, ServletException {
		logger.info("target={}, request={}", target, request.getRequestURI());
		if (target.equalsIgnoreCase("/status")) {
			response.setStatus(200);
			response.getWriter().write("OK");
			baseRequest.setHandled(true);
			return;
		}
		String bucketName = request.getParameter("bucket");
		if (StringUtils.isBlank(bucketName)) {
			throw new IllegalArgumentException("Bucket not provided");
		}
		String objectPath = request.getParameter("object");
		if (StringUtils.isBlank(objectPath)) {
			throw new IllegalArgumentException("Object path not provided");
		}
		S3Client client = S3Client.builder().credentialsProvider(EnvironmentVariableCredentialsProvider.create())
				.build();
		ResponseInputStream<GetObjectResponse> s3Response = client
				.getObject(GetObjectRequest.builder().bucket(bucketName).key(objectPath).build());
		String contents = IOUtils.toString(s3Response, StandardCharsets.UTF_8);
		response.getWriter().write(contents);
		baseRequest.setHandled(true);
	}

	public static void main(String[] args) throws Exception {
		Server server = new Server(8090);
		server.setHandler(new Main());
		logger.info("Starting server");
		server.start();
		logger.info("Started");
		server.join();
		logger.info("Joined");
	}
}
